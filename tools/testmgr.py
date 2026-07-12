#!/usr/bin/env python3
"""testmgr.py — adaptive parallel test manager (feature-parallel-test-harness).

An alternative FRONT END to the existing Makefile gate: serial `make test`
stays the reference implementation.  This tool asks make what it would run
(`make -n <target>`), splits the recipe into independent compile+check jobs,
and schedules them adaptively against live cpu/memory headroom sampled from
/proc/stat and /proc/meminfo.

Design (ticket feature-parallel-test-harness):
  * declarative job list GENERATED from Makefile targets, never a rewrite
  * job cost classes (pascal26 compile / tiny run / qemu cross / corpus)
  * calibrated timeouts: a probe compile at startup scales every budget,
    so a Pi 1 gets minutes where a workstation gets seconds
  * per-job setsid process group -> kill is total (no orphan qemu)
  * memory watchdog: on pressure kill the NEWEST job and requeue it
  * global deadline, SIGINT = full teardown
  * tiers quick/limited/full, deterministic fixed-order report,
    exit code = gate verdict

Usage:
  tools/testmgr.py --tier quick|limited|full|opt [--jobs N] [--serial]
                   [--fail-fast] [--list] [--deadline SECS]
                   [--inject-hang]   # self-test: prove hang handling
  tools/testmgr.py --bench           # tracked benchmark run -> tstate/bench.tsv
"""

import argparse
import fnmatch
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPILER = os.environ.get("TESTMGR_COMPILER", "compiler/pascal26")

# ---------------------------------------------------------------- tiers ----
# Targets per tier, in REPORT order.  quick = inner loop; limited = quick +
# self-host fixedpoint chain (test-smoke prints both) + the native gate +
# C conformance; full = everything: cross targets + corpus.  Serial `make
# test` = test-core test-threads test-asm test-debug-g lib-fpc-clean.
TIERS = {
    "quick": ["test-quick"],
    "native": [            # fast watcher verdict: all native, no qemu/
        "test-smoke",      # corpus/conformance — cross runs in the full
        "test-core", "test-threads", "test-asm", "test-debug-g",   # backfill
        "lib-fpc-clean",
    ],
    "limited": [
        "test-smoke",          # test-quick + self-host byte-identity chain
        "test-core", "test-threads", "test-asm", "test-debug-g",
        "lib-fpc-clean",
        "test-c-conformance",
    ],
    "full": [
        "test-smoke",
        "test-core", "test-threads", "test-asm", "test-debug-g",
        "lib-fpc-clean",
        "test-c-conformance",
        "test-float-determinism", "test-emit-obj",
        "test-i386", "test-aarch64", "test-arm32", "test-riscv32",
        # the 220-program c-testsuite battery per cross target, + lua on all
        # four: this matrix found 3 real backend gaps on the day it landed,
        # so the watcher should be the one running it (Track C asked for it in
        # feature-testmgr-enroll-c-cross-conformance)
        "test-c-conformance-i386", "test-c-conformance-aarch64",
        "test-c-conformance-arm32", "test-c-conformance-riscv32",
        "test-lua-cross",
        "test-lua", "test-cjson", "test-zlib",
        "test-sqlite-threads-x86_64", "test-sqlite-threads-i386",
        "test-sqlite-threads-aarch64", "test-sqlite-threads-arm32",
    ],
    # opt: O-level differential gate (feature-testmgr-opt-tier-and-benchmarks).
    # test-opt = hand-picked corpus + -O1/-O2 self-compile fixedpoints; on top,
    # generate() adds OPT_SHARDS optdiff.sh jobs sweeping EVERY test/*.pas|.c
    # at -O0 vs -O2/-O3 (stdout+rc must match). Idle watcher work, not `full`.
    "opt": ["test-opt"],
}

# The conformance battery (~220 programs behind one script) is a wall-time
# pole as a single job: fan it out with the script's --shard support.
CONFORMANCE_SHARDS = 6
# Same idea for the ~900-program optdiff sweep (tier opt).
OPT_SHARDS = 6

# ---------------------------------------------------------- cost classes ---
# est_mem: bytes we expect the job to occupy at peak (pascal26 maps a large
# BSS; corpus compiles are the heaviest).  timeout: seconds at scale 1.0 on
# the reference box; multiplied by the calibration factor at startup.
CLASSES = {
    "unit":        {"est_mem": 700 << 20,  "timeout": 90},
    "qemu":        {"est_mem": 800 << 20,  "timeout": 240},
    "selfhost":    {"est_mem": 1200 << 20, "timeout": 600},
    "corpus":      {"est_mem": 1400 << 20, "timeout": 1200},
    "conformance": {"est_mem": 1000 << 20, "timeout": 1200},
    "opt":         {"est_mem": 700 << 20,  "timeout": 900},
}
# tiers that carry the FPC cold-start canary (advisory; see fpc_canary_job).
# Not "quick": that is the inner loop and an FPC compile of compiler.pas is a
# whole build, not an inner-loop cost.
FPC_CANARY_TIERS = ("native", "limited", "full")
MEM_FLOOR = 1500 << 20          # never admit below this MemAvailable
SWAP_FLOOR = 1000 << 20         # never admit with less free swap than this
PSI_ADMIT = 20.0                # never admit above this memory PSI (some avg10)
PSI_KILL = 45.0                 # kill+requeue the newest job above this PSI
SCOPE_MAX_FRAC = 0.60           # cgroup MemoryMax = min(8G, this * MemTotal)
SCOPE_MAX_ABS = 8 << 30
SCOPE_SWAP_MAX = 1 << 30
PROBE_REF = 0.35                # seconds: hello.pas compile on reference box
TICK = 0.5

# ------------------------------------------------------- learned metrics ---
# Per-job EWMA of duration (calibration-normalized), peak session RSS and cpu
# cores actually used, learned across runs on THIS box (host-specific, so
# gitignored).  Replaces the coarse per-class guesses for admission, launch
# order and hang detection once a job has been seen enough times.
METRICS_PATH = os.path.join(REPO, ".testmgr", "metrics.json")
METRICS_MIN_RUNS = 2            # trust a job's metrics from its Nth pass
METRICS_ALPHA = 0.4             # EWMA weight of the newest observation


def load_metrics():
    try:
        with open(METRICS_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_metrics(m):
    os.makedirs(os.path.dirname(METRICS_PATH), exist_ok=True)
    tmp = METRICS_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(m, f, indent=1, sort_keys=True)
    os.replace(tmp, METRICS_PATH)


LIVE_PATH = os.path.join(REPO, ".testmgr", "live.json")
# default work-weights for jobs with no learned duration yet, per class —
# used only for the progress estimate, never for scheduling
CLASS_WEIGHT = {"unit": 1.0, "qemu": 2.0, "selfhost": 60.0,
                "corpus": 45.0, "conformance": 90.0, "opt": 30.0}


def write_json_atomic(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def sample_sessions(sids):
    """One /proc sweep: {session id: (rss_bytes, cpu_seconds)} for the given
    session leaders.  cpu includes reaped children (cutime/cstime) plus live
    members, so a job's cores-used = cpu_seconds / wall."""
    agg = {s: [0, 0.0] for s in sids}
    hz = os.sysconf("SC_CLK_TCK")
    page = os.sysconf("SC_PAGE_SIZE")
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/stat" % pid) as f:
                st = f.read()
        except OSError:
            continue
        rest = st[st.rindex(")") + 2:].split()   # fields after comm
        sid = int(rest[3])
        if sid not in agg:
            continue
        agg[sid][0] += int(rest[21]) * page                    # rss
        agg[sid][1] += (int(rest[11]) + int(rest[12]) +        # utime+stime
                        int(rest[13]) + int(rest[14])) / hz    # +children
    return agg

COMPILE_RE = re.compile(r"^\.?/?" + re.escape(COMPILER) + r"\b")
# corpus trees under library_candidates/ are gitignored scratch; a box that
# hasn't fetched them must SKIP the jobs that reference them, not fail them
CORPUS_RE = re.compile(r"library_candidates/([^/\s\"']+)")

# private per-run substitute for the recipes' literal /tmp/ paths (see
# Job.script); created in main(), world-unreadable is not needed — /tmp
# hygiene only, the OS reaps it
RUN_TMP = "/tmp/testmgr-scratch-%d" % os.getpid()

# A whole /tmp path token — including the bare DIRECTORY form.  The old plain
# str.replace of "/tmp/" missed `LD_LIBRARY_PATH=/tmp`, so recipes that built a
# .so into /tmp/libfoo.so (rewritten into private scratch) then pointed the
# loader at /tmp (not rewritten) could not find their own library.  Those jobs
# only passed on boxes where a stale /tmp/libfoo.so from an earlier serial
# `make` happened to survive; on a freshly booted box they were red.
# The lookahead keeps /tmpfoo and /tmp.bak alone.
TMP_RE = re.compile(r"/tmp(?![\w.-])(?:/[A-Za-z0-9_.+-]+)*")


def pinned_tmp_paths(lines):
    """Literal /tmp paths hardcoded inside the SOURCES a job compiles.

    A source that says `external '/tmp/liblazycasing.so'` bakes that path into
    the binary, so the recipe line that builds the .so must keep writing there
    — rewriting it into private scratch would just hide the library from the
    loader.  Everything else in the job still gets privatized.

    Reads the sources named by the recipe (Job.src is a truncated display
    string, so it cannot be used here).
    """
    out = set()
    for path in SRC_RE.findall("\n".join(lines)):
        try:
            with open(os.path.join(REPO, path), errors="replace") as f:
                out.update(TMP_RE.findall(f.read()))
        except OSError:
            continue
    return {p for p in out if p != "/tmp"}


class Job:
    def __init__(self, target, index, lines):
        self.target = target
        self.index = index
        self.lines = lines
        self.cls = classify(lines)
        # exclusive resources: two xvfb-run jobs race on the same X display
        self.resources = {"xvfb"} if "xvfb-run" in "\n".join(lines) else set()
        self.name = "%s#%02d" % (target, index)
        self.src = extract_src(lines)
        self.deps = []            # jobs that must PASS before this launches
        self.proc = None
        self.t0 = self.t1 = None
        self.timeout = None       # set after calibration
        self.status = "queued"    # queued|running|pass|fail|timeout|skipped|skip
        self.logpath = None
        self.requeued = False
        self.sel = None           # stable selector; set by assign_selectors()
        # advisory: reported, ticketed by twatch, but NOT part of the gate —
        # its failure does not turn the run RED or change the exit code.  For
        # coverage of paths nothing day-to-day depends on (the FPC cold-start
        # seed), where a red is a notice to the owning track, not a stop-work.
        self.advisory = False
        self.est_mem = CLASSES[self.cls]["est_mem"]   # refined from metrics
        self.exp_dur = None       # learned expected duration (scaled secs)
        self.exp_cores = 1.0      # learned cpu cores actually used
        self.peak_rss = 0         # observed this run (session-wide)
        self.cpu_sec = 0.0        # observed this run (incl. reaped children)

    def script(self):
        # Emulate make exactly: each logical recipe line is judged by ITS
        # overall exit status (last command) — no `set -e`, which would abort
        # mid-line on intermediate nonzero rc (`bin; test "$?" = "20"`).
        #
        # All literal /tmp/ paths are rewritten into this run's PRIVATE
        # scratch dir: recipe temp names are fixed (/tmp/pascal26-next, ...),
        # so two testmgr runs on one box — a dev gate and the watcher, say —
        # would interleave in each other's self-host chains and corrupt both
        # (observed 2026-07-08: fixedpoint byte-diff with a clean tree).
        # Rewrite happens ONLY here at execution; job.lines stays verbatim
        # for reports, and a human running the printed repro in plain /tmp
        # is fine — they're not racing themselves.
        #
        # EXCEPT paths a compiled SOURCE hardcodes.  test_c_lazycasing.pas has
        # `external '/tmp/liblazycasing.so'` baked into the binary, so building
        # that .so into our private scratch just means the loader can't find it.
        # We cannot rewrite the source, so we leave exactly those literals in
        # real /tmp and privatize everything else.  Track C ticket
        # bug-test-hardcoded-tmp-so-path retires the last of them.
        pinned = pinned_tmp_paths(self.lines)
        parts = ["cd %s || exit 1" % shlex.quote(REPO)]
        for ln in self.lines:
            if ln.strip().startswith("#"):
                continue                      # recipe comment: shell no-op
            body = TMP_RE.sub(
                lambda m: m.group(0) if m.group(0) in pinned
                else RUN_TMP + m.group(0)[len("/tmp"):], ln)
            parts.append("{\n%s\n} || exit $?" % body)
        return "\n".join(parts) + "\n"


# repo-relative source files a job touches — the human answer to "which test
# IS test-core#601?" without mapping job numbers back to Makefile lines
SRC_RE = re.compile(r"\b(?:test|lib|examples|tools|compiler)/[A-Za-z0-9_./+-]*"
                    r"\.[A-Za-z0-9]+\b")


def extract_src(lines):
    seen = []
    for m in SRC_RE.finditer("\n".join(lines)):
        if m.group(0) not in seen:
            seen.append(m.group(0))
    if not seen:
        return ""
    extra = " +%d" % (len(seen) - 2) if len(seen) > 2 else ""
    return " ".join(seen[:2]) + extra


def job_sources(job):
    """Every repo source path a job's recipe names (not the truncated src)."""
    seen = []
    for m in SRC_RE.finditer("\n".join(job.lines)):
        if m.group(0) not in seen:
            seen.append(m.group(0))
    return seen


def job_selector(job):
    """The most durable --job selector for this job.

    Prefer the first source it compiles (stable across renumbering); fall back
    to the positional name for jobs that name no source (a few corpus/prologue
    jobs), which is the best that exists for them.
    """
    # shard names (test-c-conformance#shard0/6, optdiff#shard3/8) are NOT
    # positional indices into a recipe — they are already stable, and they say
    # which shard, which src: cannot.  Keep them.
    if "#shard" in job.name:
        return job.name
    srcs = job_sources(job)
    if not srcs:
        return job.name
    # qualify with the target: the same test/foo.pas is compiled by test-core
    # AND by every cross target, so a bare src: would select all of them.
    return "%s#src:%s" % (job.target, srcs[0])


def assign_selectors(jobs):
    """Give every job a UNIQUE stable selector (job.sel).

    A handful of sources are compiled more than once inside one target (hello.pas
    at different flags, say), so the plain source selector is ambiguous for them
    — and an ambiguous selector would merge two jobs' red/green history into one.
    Suffix those with @1, @2 ... in recipe order.  That still only shifts if the
    number of times THAT source appears in THAT target changes, which is a far
    rarer event than "a test was inserted somewhere above" (the thing that
    renumbers every positional name after it).
    """
    # Ambiguity is about what the selector SELECTS, not just which jobs share a
    # first source: a job that merely mentions records.pas as a secondary source
    # is still matched by src:test/records.pas.  So group by the actual match set.
    srcs = {id(j): job_sources(j) for j in jobs}
    groups = {}
    for j in jobs:
        base = job_selector(j)
        if not base.startswith(j.target + "#src:"):
            continue                          # no source: keeps its name
        path = base.split("#src:", 1)[1]
        groups[base] = [k for k in jobs
                        if k.target == j.target and path in srcs[id(k)]]
    for j in jobs:
        base = job_selector(j)
        grp = groups.get(base)
        if grp is None or len(grp) == 1:
            j.sel = base
        else:
            j.sel = "%s@%d" % (base, grp.index(j) + 1)


def job_selected(job, sel):
    """--job selector: `target#NN` glob, or the STABLE `src:<path>` form.

    `test-core#665` is a positional index into the target's recipe lines, so
    inserting a test renumbers every job after it.  That makes a job number
    useless as a durable name: a ticket filed against test-core#665 pointed at
    a different test by the time it was triaged the same day, and a bisect that
    re-runs "#665" at an older commit is not even running the failing test.
    `src:test/test_c_gtk_window.pas` selects the job that COMPILES that source,
    and survives renumbering — it is what twatch records and bisects on.

    Forms:
      <target>#src:<path>[@N]  — the exact selector twatch records (job.sel)
      src:<path>               — any target that compiles <path>
      <target>#NN              — the positional name (fnmatch); still accepted,
                                 but do not persist it anywhere
    """
    if job.sel and sel == job.sel:
        return True
    target, _, rest = sel.partition("#")
    if rest.startswith("src:"):
        if target != job.target:
            return False
        sel = rest
    if sel.startswith("src:"):
        pat = sel[4:]
        if "@" in pat:
            # an explicit @N names ONE job and we already failed the exact
            # job.sel test above.  Do NOT fall back to matching the bare path:
            # that would quietly select every sibling compile of that source.
            # A stale @N therefore matches nothing, and testmgr says so.
            return False
        return any(fnmatch.fnmatch(s, pat) or s == pat
                   for s in job_sources(job))
    return fnmatch.fnmatch(job.name, sel)


def classify(lines):
    text = "\n".join(lines)
    if "optdiff.sh" in text:
        return "opt"
    if "compiler.pas" in text or "compiler/compiler.pas" in text:
        return "selfhost"
    if "run_c_conformance" in text:
        return "conformance"
    if ("library_candidates" in text or "lua_runner" in text
            or "sqlite" in text or "zlib" in text or "/lua/" in text):
        return "corpus"
    if "run_target.sh" in text or "qemu" in text:
        return "qemu"
    return "unit"


# ------------------------------------------------------------ generation ---
def make_dry_run(target):
    r = subprocess.run(["make", "-n", "--no-print-directory", target],
                       cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("testmgr: make -n %s failed:\n%s" % (target, r.stderr))
    lines, cont = [], None
    for ln in r.stdout.splitlines():
        if cont is not None:                 # inside a backslash continuation
            cont += "\n" + ln
            if not ln.rstrip().endswith("\\"):
                lines.append(cont)
                cont = None
            continue
        if not ln.strip():
            continue
        if ln.startswith("make[") or ln.startswith("make:"):
            continue
        if ln.rstrip().endswith("\\"):
            cont = ln
        else:
            lines.append(ln)
    if cont is not None:
        lines.append(cont)
    return lines


def split_jobs(target, lines):
    """Group recipe lines into jobs.  A new job starts at a compiler
    invocation that FOLLOWS at least one non-compile line in the current
    group — so compile/compile/compare golden patterns (test-i386 style)
    stay atomic, while compile/check pairs (test-core style) split."""
    groups, cur, cur_has_check = [], [], False
    for ln in lines:
        if COMPILE_RE.match(ln.strip()) and cur and cur_has_check:
            groups.append(cur)
            cur, cur_has_check = [], False
        cur.append(ln)
        if not COMPILE_RE.match(ln.strip()):
            cur_has_check = True
    if cur:
        groups.append(cur)
    # Merge groups that touch the same /tmp scratch file.  A recipe may
    # compile an artifact in one line and consume it many lines later
    # (test-emit-obj builds test_emit_obj_rv.o, then links it after the
    # xtensa block) — the split above puts producer and consumer in
    # DIFFERENT jobs, which have no ordering between them, and a
    # standalone `--job` repro runs the consumer with a fresh scratch dir
    # where the artifact never existed.  Shared scratch file = cross-job
    # dependency = must stay one job.
    #
    # One producer/consumer edge is invisible to a filename scan: a recipe
    # builds /tmp/libfoo.so and a LATER line runs a binary with
    # LD_LIBRARY_PATH=/tmp, naming the library nowhere — the loader finds it by
    # soname.  So the consumer shares no /tmp *filename* with its producer and
    # the two stay in different jobs with no ordering between them (seen
    # 2026-07-12: test-core#555/#556 red on a freshly booted box, green
    # everywhere a stale /tmp/libspill.so from an old serial `make` happened to
    # survive).  Model the loader search path itself as the shared resource:
    # every .so producer and every bare-/tmp LD_LIBRARY_PATH consumer in a
    # target gets a synthetic token, which the union-find below merges as usual.
    tmp_re = re.compile(r"/tmp/[A-Za-z0-9_./+-]+")
    so_prod_re = re.compile(r"-o\s+/tmp/\S+\.so\b")
    loader_dir_re = re.compile(r"LD_LIBRARY_PATH=/tmp(?![\w./-])")
    LOADER_DIR = "\0so-loader-dir"
    parent = list(range(len(groups)))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    owner = {}
    for i, g in enumerate(groups):
        text = "\n".join(g)
        toks = set(tmp_re.findall(text))
        if so_prod_re.search(text) or loader_dir_re.search(text):
            toks.add(LOADER_DIR)
        for f in toks:
            if f in owner:
                a, b = find(owner[f]), find(i)
                if a != b:
                    parent[max(a, b)] = min(a, b)
            else:
                owner[f] = i
    if any(find(i) != i for i in range(len(groups))):
        buckets = {}
        for i, g in enumerate(groups):
            buckets.setdefault(find(i), []).extend(g)
        groups = [buckets[k] for k in sorted(buckets)]
    jobs = []
    for i, g in enumerate(groups):
        jobs.append(Job(target, i, g))
    # a leading group with no compiler invocation is a prologue every other
    # job in this target depends on (setup lines: rm, mkdir, env checks)
    if len(jobs) > 1 and not any(COMPILE_RE.match(l.strip()) for l in jobs[0].lines):
        for j in jobs[1:]:
            j.deps.append(jobs[0])
    return jobs


def generate(tier):
    jobs = []
    for tgt in TIERS[tier]:
        for job in split_jobs(tgt, make_dry_run(tgt)):
            if job.cls == "conformance" and CONFORMANCE_SHARDS > 1:
                for i in range(CONFORMANCE_SHARDS):
                    lines = [ln + " --shard %d/%d" % (i, CONFORMANCE_SHARDS)
                             for ln in job.lines]
                    shard = Job(tgt, i, lines)
                    shard.name = "%s#shard%d/%d" % (tgt, i, CONFORMANCE_SHARDS)
                    jobs.append(shard)
            else:
                jobs.append(job)
    if tier == "opt":
        for i in range(OPT_SHARDS):
            j = Job("optdiff", i,
                    ["tools/optdiff.sh --shard %d/%d" % (i, OPT_SHARDS)])
            j.name = "optdiff#shard%d/%d" % (i, OPT_SHARDS)
            jobs.append(j)
    if tier in FPC_CANARY_TIERS:
        jobs.append(fpc_canary_job())
    assign_selectors(jobs)
    return jobs


def corpus_warning(absent, njobs):
    """The loud, actionable version of 'N jobs skipped'.

    `absent` maps corpus tree -> how many jobs it silences (a job may name two
    trees, so these do NOT sum to `njobs` — the headline count must be the
    distinct-job one, or it contradicts the report's skip line).  Names the
    trees and prints the exact fetch command, because the failure mode this
    guards against is a box reporting GREEN for tests it never ran.
    """
    names = sorted(absent)
    width = max(len(n) for n in names)
    lines = ["",
             "  " + "!" * 68,
             "  !! CORPUS MISSING — %d job(s) will SKIP, not run." % njobs,
             "  !! A green verdict here does NOT cover them.",
             "  !!"]
    for n in names:
        lines.append("  !!   %-*s  %3d job(s)" % (width, n, absent[n]))
    lines += ["  !!",
              "  !! Fetch them (gitignored, nothing enters the repo):",
              "  !!   tools/install_lib_candidates.sh %s" % " ".join(names),
              "  " + "!" * 68, ""]
    return "\n".join(lines)


def fpc_canary_job():
    """`make bootstrap`'s FIRST line: does FPC still accept our own source?

    The FPC seed is the cold-start path — the only way to rebuild the compiler
    on a box with no blessed pascal26, and the escape hatch when a self-hosted
    binary is lost.  Nothing day-to-day uses it, so it rots silently: master sat
    broken for an unknown time (a forward decl whose parameter got renamed, a
    routine that moved) because every normal build starts from the self-hosted
    seed.  Each break is trivial the day it lands and archaeology a year later.

    Compile-only: no fixedpoint, no bootstrap chain.  "FPC still accepts the
    source" IS the signal.  ADVISORY — a red here is a notice for Track A
    (it's compiler/** drift), not a gate on anyone's push.
    """
    out = "/tmp/p26_fpc_canary"                    # -> private scratch
    cmd = " ".join([FPC_BIN] + FPC_FLAGS +
                   ["-FU" + out + "_u", "-FE" + out + "_u",
                    "-o" + out, COMPILER_SRC.strip('"')])
    j = Job("fpc-bootstrap", 0,
            ["mkdir -p %s_u && %s" % (out, cmd)])
    j.name = "fpc-bootstrap#00"
    j.cls = "selfhost"
    j.advisory = True
    j.est_mem = CLASSES["selfhost"]["est_mem"]
    return j


# -------------------------------------------------------------- sampling ---
def meminfo():
    """The /proc/meminfo fields we schedule against, in bytes."""
    want = ("MemAvailable:", "MemTotal:", "SwapFree:", "SwapTotal:")
    out = {}
    with open("/proc/meminfo") as f:
        for ln in f:
            k = ln.split(":", 1)[0]
            if ln.startswith(want):
                out[k] = int(ln.split()[1]) << 10
    return out


def mem_available():
    return meminfo().get("MemAvailable", 0)


def mem_pressure():
    """`some avg10` from /proc/pressure/memory: percent of the last 10s in
    which at least one task stalled on memory.

    This is the signal MemAvailable cannot give us.  A box that is swapping
    hard still reports gigabytes "available" (MemAvailable counts reclaimable
    page cache and knows nothing about swap), so reclaim looks healthy right
    up to the point the desktop stops scheduling — that is how the 2026-07-12
    freeze got past admission.  PSI measures the stall itself, so it rises
    while the box is still saveable.  Returns 0.0 where PSI is unavailable
    (pre-4.20 kernel, CONFIG_PSI off), which degrades us to the old behaviour
    rather than blocking every job.
    """
    try:
        with open("/proc/pressure/memory") as f:
            for ln in f:
                if ln.startswith("some "):
                    for field in ln.split()[1:]:
                        k, _, v = field.partition("=")
                        if k == "avg10":
                            return float(v)
    except (OSError, ValueError):
        pass
    return 0.0


def cpu_times():
    with open("/proc/stat") as f:
        parts = f.readline().split()
    vals = list(map(int, parts[1:]))
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
    return idle, sum(vals)


# -------------------------------------------------------------- executor ---
class Manager:
    def __init__(self, jobs, args, scale, logdir):
        self.jobs = jobs
        self.args = args
        self.scale = scale
        self.logdir = logdir
        self.running = []
        self.nproc = os.cpu_count() or 1
        self.last_stall_msg = 0.0
        self.metrics = load_metrics()
        for j in jobs:
            cls_to = CLASSES[j.cls]["timeout"]
            m = self.metrics.get(j.name)
            if m and m.get("n", 0) >= METRICS_MIN_RUNS:
                j.exp_dur = m["dur"] * scale
                j.exp_cores = min(float(self.nproc), max(0.1, m.get("cpu", 1.0)))
                j.est_mem = max(64 << 20, int(m["mem"] * 1.4))
                # hang detection: a job far past its OWN expected duration is
                # killed long before the coarse class timeout would fire; the
                # class/4 floor absorbs environment shifts (corpus trees
                # appearing turns a 2s skip into a 100s real run)
                if j.timeout is None:
                    j.timeout = min(cls_to * scale,
                                    max(45.0, j.exp_dur * 10 + 15,
                                        cls_to * scale / 4))
            if j.timeout is None:
                j.timeout = cls_to * scale
        # launch longest-expected jobs first: the critical path (corpus,
        # conformance shards, selfhost chains) must start at t=0, not after
        # 600 unit jobs have churned through.  Report order stays generation
        # order — this only affects launch order.
        self.queue = sorted(jobs, key=lambda j: -(j.exp_dur if j.exp_dur
                                                  else CLASSES[j.cls]["timeout"]))
        # cores/mem-aware admission does the real throttling; the cap is just
        # a runaway guard, and >nproc lets io/qemu-idle jobs keep cores busy
        self.hard_cap = 1 if args.serial else (args.jobs or self.nproc * 2)
        self.prev_cpu = cpu_times()
        self.idle_frac = 1.0
        self.interrupted = False
        self.deadline = time.monotonic() + args.deadline

    # -- lifecycle -----------------------------------------------------
    def launch(self, job):
        job.logpath = os.path.join(self.logdir, job.name.replace("/", "_") + ".log")
        logf = open(job.logpath, "wb")
        def presetup():
            os.setsid()
            try:
                os.nice(10)
            except OSError:
                pass
        job.proc = subprocess.Popen(["sh", "-c", job.script()],
                                    stdout=logf, stderr=subprocess.STDOUT,
                                    preexec_fn=presetup, cwd=REPO)
        logf.close()
        job.t0 = time.monotonic()
        job.status = "running"
        self.running.append(job)

    def kill_group(self, job, sig=signal.SIGKILL):
        try:
            os.killpg(job.proc.pid, sig)
        except (ProcessLookupError, PermissionError):
            pass

    def reap(self):
        done = []
        now = time.monotonic()
        for job in list(self.running):
            rc = job.proc.poll()
            if rc is not None:
                job.t1 = now
                job.status = "pass" if rc == 0 else "fail"
                self.running.remove(job)
                done.append(job)
                if job.status == "pass":
                    self.learn(job)
            elif now - job.t0 > job.timeout:
                self.kill_group(job)
                job.proc.wait()
                job.t1 = now
                job.status = "timeout"
                self.running.remove(job)
                done.append(job)
        return done

    def sample(self):
        idle, total = cpu_times()
        pidle, ptotal = self.prev_cpu
        if total > ptotal:
            self.idle_frac = (idle - pidle) / (total - ptotal)
        self.prev_cpu = (idle, total)
        if self.running:      # per-job session RSS / cpu (metrics learning)
            agg = sample_sessions({j.proc.pid for j in self.running})
            for j in self.running:
                rss, cpu = agg.get(j.proc.pid, (0, 0.0))
                j.peak_rss = max(j.peak_rss, rss)
                j.cpu_sec = max(j.cpu_sec, cpu)

    def job_weight(self, job):
        return job.exp_dur or CLASS_WEIGHT[job.cls]

    def write_live(self, wall_t0):
        """Progress contract for frontends (./trackt, web): weighted % from
        learned expected durations — done/total job counts alone lie when one
        conformance shard outweighs a thousand unit compiles."""
        total_w = sum(self.job_weight(j) for j in self.jobs) or 1.0
        done_w = sum(self.job_weight(j) for j in self.jobs
                     if j.status in ("pass", "fail", "timeout", "skipped"))
        run_w = sum(min(time.monotonic() - j.t0, self.job_weight(j))
                    for j in self.running if j.t0)
        pct = min(99.0, 100.0 * (done_w + run_w) / total_w)
        red = [j.name for j in self.jobs if j.status in ("fail", "timeout")]
        elapsed = time.monotonic() - wall_t0
        write_json_atomic(LIVE_PATH, {
            "ts": time.time(), "tier": self.args.tier, "pct": round(pct, 1),
            "done": self.done_count(), "total": len(self.jobs),
            "elapsed": round(elapsed, 1),
            "eta": round(elapsed * (100 - pct) / pct, 1) if pct > 1 else None,
            "running": [{"name": j.name,
                         "elapsed": round(time.monotonic() - j.t0, 1),
                         "exp": round(self.job_weight(j), 1)}
                        for j in sorted(self.running, key=lambda j: j.t0)],
            "red": red,
            "red_src": {j.name: j.src for j in self.jobs
                        if j.status in ("fail", "timeout") and j.src}})

    def learn(self, job):
        """EWMA the passing run into the per-box metrics store."""
        dur = max(0.05, (job.t1 - job.t0) / self.scale)
        cores = 1.0 if (job.t1 - job.t0) < 0.75 or job.cpu_sec <= 0 \
            else min(float(self.nproc), job.cpu_sec / (job.t1 - job.t0))
        # a job whose RSS never got sampled (finished inside a tick, or the
        # /proc scan missed its children) must NOT learn a 32 MB footprint —
        # that used to let a swarm of self-compile/optdiff shards, each really
        # hundreds of MB, all pass admission at once.  Fall back to the class
        # estimate, which is honest about the pascal26 BSS.
        mem = job.peak_rss if job.peak_rss > 0 else CLASSES[job.cls]["est_mem"]
        m = self.metrics.get(job.name)
        if not m:
            self.metrics[job.name] = {"dur": round(dur, 2), "mem": mem,
                                      "cpu": round(cores, 2), "n": 1}
            return
        a = METRICS_ALPHA
        m["dur"] = round((1 - a) * m["dur"] + a * dur, 2)
        m["mem"] = int((1 - a) * m["mem"] + a * mem)
        m["cpu"] = round((1 - a) * m.get("cpu", 1.0) + a * cores, 2)
        m["n"] = m.get("n", 0) + 1

    def admit_ok(self, job, now):
        if len(self.running) >= self.hard_cap:
            return False
        if job.resources and any(job.resources & r.resources for r in self.running):
            return False
        if self.running and self.idle_frac < 0.10:
            return False
        # don't oversubscribe cpu with jobs KNOWN to be compute-hungry —
        # io/qemu-idle jobs (cores < 1) pack denser and keep the box busy
        if (sum(j.exp_cores for j in self.running) + job.exp_cores
                > self.nproc + 1):
            return False
        # swap + PSI gates: MemAvailable stays optimistic on a swapping box
        # (it ignores swap entirely), so these are the guards that actually
        # see the refault storm coming.  Report the stall once per run rather
        # than silently idling — a stuck-looking scheduler must say why.
        mi = meminfo()
        if mi.get("SwapTotal", 0) and mi.get("SwapFree", 0) < SWAP_FLOOR:
            self.note_stall("swap low (%d MB free)" % (mi["SwapFree"] >> 20))
            return False
        psi = mem_pressure()
        if psi > PSI_ADMIT:
            self.note_stall("memory pressure (PSI some avg10 %.1f%%)" % psi)
            return False
        # charge est_mem for jobs too young for their RSS to show up yet
        uncharged = sum(j.est_mem
                        for j in self.running if now - j.t0 < 5.0)
        avail = mi.get("MemAvailable", 0) - uncharged
        return avail - job.est_mem > MEM_FLOOR

    def note_stall(self, why):
        """Print a memory-stall reason at most once every 30s."""
        now = time.time()
        if now - self.last_stall_msg < 30.0:
            return
        self.last_stall_msg = now
        print("testmgr: admission held — %s" % why, flush=True)

    def deps_ready(self, job):
        for d in job.deps:
            if d.status == "queued" or d.status == "running":
                return None
            if d.status != "pass":
                return False
        return True

    def watchdog(self):
        # two independent trips: the old MemAvailable floor (a box running out
        # of RAM outright) and memory PSI (a box that is *thrashing* — plenty
        # of MemAvailable on paper, but every task is stalling on refaults).
        # The 2026-07-12 freeze only ever showed the second one.
        psi = mem_pressure()
        if mem_available() >= (MEM_FLOOR >> 1) and psi < PSI_KILL:
            return
        if len(self.running) <= 1:
            return          # single job: let its own timeout decide
        newest = max(self.running, key=lambda j: j.t0)
        self.kill_group(newest)
        newest.proc.wait()
        self.running.remove(newest)
        if newest.requeued:
            newest.status = "fail"
        else:
            newest.requeued = True
            newest.status = "queued"
            self.queue.append(newest)
            print("testmgr: memory pressure (%s) — killed %s, requeued"
                  % ("PSI some avg10 %.1f%%" % psi if psi >= PSI_KILL
                     else "MemAvailable %d MB" % (mem_available() >> 20),
                     newest.name), flush=True)

    def teardown(self):
        for job in self.running:
            self.kill_group(job)
        for job in self.running:
            try:
                job.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.kill_group(job)
        for job in self.running:
            job.status = "fail"
            job.t1 = time.monotonic()
        self.running = []

    # -- main loop -----------------------------------------------------
    def run(self):
        signal.signal(signal.SIGINT, self._sigint)
        signal.signal(signal.SIGTERM, self._sigint)
        failed = False
        self._wall_t0 = time.monotonic()
        self._last_live = 0.0
        while self.queue or self.running:
            if self.interrupted:
                print("\ntestmgr: SIGINT — tearing down all jobs", flush=True)
                self.teardown()
                for j in self.queue:
                    j.status = "skipped"
                self.queue = []
                return 130
            if time.monotonic() > self.deadline:
                print("testmgr: GLOBAL DEADLINE exceeded — tearing down", flush=True)
                self.teardown()
                for j in self.queue:
                    j.status = "skipped"
                self.queue = []
                return 1
            for job in self.reap():
                dur = job.t1 - job.t0
                mark = {"pass": "ok", "fail": "FAIL", "timeout": "TIMEOUT"}[job.status]
                if job.advisory and job.status != "pass":
                    mark = "NOTICE"
                print("  [%4d/%d] %-7s %-28s %6.1fs" %
                      (self.done_count(), len(self.jobs), mark, job.name, dur),
                      flush=True)
                if job.status != "pass" and not job.advisory:
                    failed = True
                    if self.args.fail_fast:
                        print("testmgr: fail-fast — tearing down", flush=True)
                        self.teardown()
                        for j in self.queue:
                            j.status = "skipped"
                        self.queue = []
                        return 1
            self.sample()
            self.watchdog()
            now = time.monotonic()
            if now - self._last_live >= 1.0:
                self._last_live = now
                self.write_live(self._wall_t0)
            launched = 0
            for job in list(self.queue):
                if launched >= self.hard_cap:   # sampler reacts next tick
                    break
                ready = self.deps_ready(job)
                if ready is False:
                    job.status = "skipped"
                    self.queue.remove(job)
                    failed = True
                    continue
                if ready is None:
                    continue
                if not self.admit_ok(job, now):
                    continue
                self.queue.remove(job)
                self.launch(job)
                launched += 1
            time.sleep(TICK)
        return 1 if failed else 0

    def done_count(self):
        return sum(1 for j in self.jobs if j.status in
                   ("pass", "fail", "timeout", "skipped"))

    def _sigint(self, *_):
        self.interrupted = True


# ------------------------------------------------------------ calibration --
def calibrate():
    """Time one known-cost compile; scale all timeouts from it so weak
    hardware never gets false timeouts."""
    t0 = time.monotonic()
    r = subprocess.run([os.path.join(REPO, COMPILER), "test/hello.pas",
                        os.path.join(RUN_TMP, "testmgr_probe26")], cwd=REPO,
                       capture_output=True)
    dt = time.monotonic() - t0
    if r.returncode != 0:
        sys.exit("testmgr: probe compile failed — is %s healthy?" % COMPILER)
    return max(1.0, dt / PROBE_REF)


def build_compiler():
    r = subprocess.run(["make", "--no-print-directory", COMPILER], cwd=REPO)
    if r.returncode != 0:
        sys.exit("testmgr: building %s failed" % COMPILER)


# ------------------------------------------------------------- benchmark ---
# --bench face (feature-testmgr-opt-tier-and-benchmarks): fixed workload
# suite spanning the regimes the -O3 campaign identified, each at every
# BENCH_LEVEL. Output equality across levels is verified FIRST (canary: a
# timing row from a miscompiled binary is worse than none), then wall time =
# min of BENCH_RUNS runs. Rows append to tstate/bench.tsv (greppable
# history); a same-host (workload, level) slower than the previous recorded
# row by >BENCH_SLOW_PCT is flagged. Serial on purpose — timing needs a
# quiet box, so this never goes through the parallel Manager.
BENCH_LEVELS = ("-O0", "-O2", "-O3")
BENCH_RUNS = 5
BENCH_SELF_RUNS = 3            # self-compile is ~10s a run: 3 is plenty
BENCH_SLOW_PCT = 10.0
BENCH_TSV_REL = "devdocs/progress/tstate/bench.tsv"
COMPILER_SRC = "compiler/compiler.pas"
# FPC comparison (feature-testmgr-fpc-compare-and-web-dashboard): the `fpc`
# level in bench.tsv times the reference compiler on the same source so the
# dashboard can show pxx-vs-FPC. Flags mirror the Makefile bootstrap.
FPC_BIN = os.environ.get("FPC", "fpc")
FPC_FLAGS = ["-O2", "-Tlinux", "-Px86_64"]
FPC_LEVEL = "fpc"
# (name, source, canary argv, timed argv, fpc_ok) — canary mode must be
# deterministic; {tmp} expands to the bench scratch dir. fpc_ok marks sources
# in the common pascal26/FPC subset (no pxx-only units) that are ALSO compiled
# and timed under `fpc -O2` for the cross-compiler `fpc` level.
BENCH_SUITE = (
    ("mandelbrot", "examples/mandelbrot/mandelbrot.pas",
     [], ["--bench", "1600", "1200"], False),       # float compute (pxx units)
    ("raytracer", "examples/raytracer/raytracer.pas",
     [], ["--ppm", "{tmp}/rt.ppm", "480", "360"], False),  # call-heavy float
    ("sieve", "examples/primes/sieve.pas", [], [], False),  # memory-bound int
    ("nbody", "bench/portable/nbody.pas", [], [], True),   # float, FPC-comparable
    ("fib", "bench/portable/fib.pas", [], [], True),       # call-heavy int, FPC-comparable
)


def bench_time(argv, runs, timeout):
    best = None
    for _ in range(runs):
        t0 = time.monotonic()
        try:
            r = subprocess.run(argv, cwd=REPO, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=timeout)
        except subprocess.TimeoutExpired:
            return None
        if r.returncode != 0:
            return None
        dt = time.monotonic() - t0
        best = dt if best is None else min(best, dt)
    return best


def fpc_build(src, out, tmp):
    """Compile `src` with FPC into `out` (units to `tmp`). Returns True on a
    clean build, False otherwise. Silent — the caller reports."""
    r = subprocess.run([FPC_BIN] + FPC_FLAGS + ["-FU" + tmp, "-FE" + tmp,
                        "-o" + out, src], cwd=REPO, capture_output=True)
    return r.returncode == 0 and os.path.exists(out)


def bench_prev(tsv, host):
    """Latest recorded ms per (workload, level) for this host."""
    prev = {}
    try:
        with open(tsv) as f:
            for ln in f:
                c = ln.rstrip("\n").split("\t")
                if len(c) >= 6 and c[1] == host:
                    try:
                        prev[(c[3], c[4])] = float(c[5])
                    except ValueError:
                        pass
    except OSError:
        pass
    return prev


def run_bench():
    import socket
    build_compiler()
    cc = os.path.join(REPO, COMPILER)
    host = re.sub(r"[^A-Za-z0-9_-]", "-",
                  socket.gethostname().split(".")[0])
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                         capture_output=True, text=True).stdout.strip()[:12]
    date = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    tsv = os.path.join(REPO, BENCH_TSV_REL)
    out_tsv = os.environ.get("TESTMGR_BENCH_TSV", tsv)   # twatch: detached
    prev = bench_prev(tsv, host)                          # checkout writes
    tmp = tempfile.mkdtemp(prefix="tbench-")              # elsewhere
    timeout = 120 * float(os.environ.get("TESTMGR_TIME_SCALE", "1"))
    fpc_present = shutil.which(FPC_BIN) is not None
    if not fpc_present:
        print("  bench: fpc not found — skipping the `fpc` comparison level")
    rows, slow, red = [], [], []

    def record(name, lvl, secs):
        ms = round(secs * 1000, 1)
        rows.append("%s\t%s\t%s\t%s\t%s\t%s" % (date, host, sha, name, lvl, ms))
        old = prev.get((name, lvl))
        note = ""
        if old and ms > old * (1 + BENCH_SLOW_PCT / 100.0):
            note = "  SLOW (was %sms)" % old
            slow.append("%s %s %s -> %sms" % (name, lvl, old, ms))
        print("  bench %-12s %-4s %8.1fms%s" % (name, lvl, ms, note), flush=True)

    for name, src, canary, timed, fpc_ok in BENCH_SUITE:
        ref = None
        for lvl in BENCH_LEVELS:
            b = os.path.join(tmp, name + lvl.replace("-", "_"))
            if subprocess.run([cc, lvl, src, b], cwd=REPO,
                              capture_output=True).returncode != 0:
                print("  bench %-12s %-4s COMPILE-FAIL" % (name, lvl))
                red.append("%s %s compile" % (name, lvl))
                continue
            argv = [b] + [a.format(tmp=tmp) for a in canary]
            try:
                c = subprocess.run(argv, cwd=REPO, capture_output=True,
                                   stdin=subprocess.DEVNULL, timeout=timeout)
                got = (c.returncode, c.stdout)
            except subprocess.TimeoutExpired:
                got = None
            if lvl == "-O0":
                ref = got
            if got is None or ref is None or got != ref:
                print("  bench %-12s %-4s CANARY-DIFF vs -O0" % (name, lvl))
                red.append("%s %s canary" % (name, lvl))
                continue
            dt = bench_time([b] + [a.format(tmp=tmp) for a in timed],
                            BENCH_RUNS, timeout)
            if dt is None:
                red.append("%s %s run" % (name, lvl))
                continue
            record(name, lvl, dt)

        # fpc comparison level: same source under the reference compiler. Not
        # a regression signal (RED) if it fails — FPC just may not accept a
        # source, and its absence is fine; only pxx levels gate.
        if fpc_ok and fpc_present:
            fb = os.path.join(tmp, name + "_fpc")
            if not fpc_build(src, fb, tmp):
                print("  bench %-12s %-4s FPC-COMPILE-FAIL" % (name, FPC_LEVEL))
            else:
                argv = [fb] + [a.format(tmp=tmp) for a in canary]
                try:
                    c = subprocess.run(argv, cwd=REPO, capture_output=True,
                                       stdin=subprocess.DEVNULL, timeout=timeout)
                    got = (c.returncode, c.stdout)
                except subprocess.TimeoutExpired:
                    got = None
                # canary on exit code only — stdout may differ in float
                # formatting between the two RTLs even when both are correct.
                if got is None or ref is None or got[0] != ref[0]:
                    print("  bench %-12s %-4s FPC-CANARY-DIFF vs -O0"
                          % (name, FPC_LEVEL))
                else:
                    dt = bench_time([fb] + [a.format(tmp=tmp) for a in timed],
                                    BENCH_RUNS, timeout)
                    if dt is not None:
                        record(name, FPC_LEVEL, dt)

    # self-compile: the memory-bound big-program case. Timed = an -OL-built
    # compiler compiling the compiler source; canary = every stage's output
    # for a fixed input must be byte-identical (optimizing the compiler must
    # not change what it emits).
    ref_out = None
    for lvl in BENCH_LEVELS:
        stage = os.path.join(tmp, "p26" + lvl.replace("-", "_"))
        if subprocess.run([cc, lvl, COMPILER_SRC, stage], cwd=REPO,
                          capture_output=True).returncode != 0:
            print("  bench %-12s %-4s COMPILE-FAIL" % ("selfcompile", lvl))
            red.append("selfcompile %s compile" % lvl)
            continue
        hello = os.path.join(tmp, "hello" + lvl.replace("-", "_"))
        subprocess.run([stage, "test/hello.pas", hello], cwd=REPO,
                       capture_output=True)
        try:
            with open(hello, "rb") as f:
                out = f.read()
        except OSError:
            out = None
        if lvl == "-O0":
            ref_out = out
        if out is None or ref_out is None or out != ref_out:
            print("  bench %-12s %-4s CANARY-DIFF vs -O0" % ("selfcompile", lvl))
            red.append("selfcompile %s canary" % lvl)
            continue
        dt = bench_time([stage, COMPILER_SRC, os.path.join(tmp, "selfout")],
                        BENCH_SELF_RUNS, timeout * 5)
        if dt is None:
            red.append("selfcompile %s run" % lvl)
            continue
        record("selfcompile", lvl, dt)

    # selfcompile `fpc` level: time the REFERENCE compiler compiling the same
    # compiler source (the historic vs-FPC compile-speed metric, now per-SHA).
    # No canary — FPC emits its own binary; this measures compile throughput.
    if fpc_present:
        ftmp = os.path.join(tmp, "fpc_self")
        os.makedirs(ftmp, exist_ok=True)
        argv = ([FPC_BIN] + FPC_FLAGS + ["-FU" + ftmp, "-FE" + ftmp,
                 "-o" + os.path.join(ftmp, "p26_fpc"), COMPILER_SRC])
        if subprocess.run(argv, cwd=REPO, capture_output=True).returncode != 0:
            print("  bench %-12s %-4s FPC-COMPILE-FAIL" % ("selfcompile",
                                                           FPC_LEVEL))
        else:
            dt = bench_time(argv, BENCH_SELF_RUNS, timeout * 5)
            if dt is not None:
                record("selfcompile", FPC_LEVEL, dt)

    if rows:
        os.makedirs(os.path.dirname(out_tsv), exist_ok=True)
        fresh = not os.path.exists(out_tsv) or not os.path.getsize(out_tsv)
        with open(out_tsv, "a") as f:
            if fresh:
                f.write("# date\thost\tsha\tworkload\tlevel\tms\n")
            f.write("\n".join(rows) + "\n")
    print("bench: %d rows -> %s%s%s" %
          (len(rows), out_tsv,
           "  SLOW: " + "; ".join(slow) if slow else "",
           "  RED: " + "; ".join(red) if red else ""), flush=True)
    return 1 if red else 0


# ------------------------------------------------------------------ main ---
def reexec_scoped():
    """Re-exec ourselves inside a memory-capped systemd scope.

    This is the guard that makes a desktop freeze structurally impossible: a
    runaway job is killed by the kernel INSIDE our own cgroup, so the rest of
    the box never enters reclaim.  It does not replace the admission/watchdog
    heuristics — those keep the run healthy — it is the backstop for when they
    are wrong (2026-07-12: they were, and the box needed a hard reset).

    MemorySwapMax is the important half.  With swap uncapped, the cgroup does
    not hit MemoryMax; it just pushes anon pages to disk and thrashes, which
    is exactly the livelock we are trying to prevent — the kernel only OOMs
    when reclaim FAILS, and swapping means reclaim keeps "succeeding".

    Degrades to a plain unscoped run wherever systemd-run is unusable (no user
    session, container, CI), so callers need no setup.
    """
    if os.environ.get("TESTMGR_SCOPED") == "1":
        return
    if not shutil.which("systemd-run"):
        return
    try:                        # is there a usable user session bus?
        probe = subprocess.run(
            ["systemd-run", "--user", "--scope", "--quiet", "true"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        if probe.returncode != 0:
            return
    except (OSError, subprocess.SubprocessError):
        return
    total = meminfo().get("MemTotal", 0)
    if not total:
        return
    cap = min(SCOPE_MAX_ABS, int(total * SCOPE_MAX_FRAC))
    os.environ["TESTMGR_SCOPED"] = "1"
    print("testmgr: scoped — MemoryMax=%dM MemorySwapMax=%dM"
          % (cap >> 20, SCOPE_SWAP_MAX >> 20), flush=True)
    try:
        os.execvp("systemd-run", [
            "systemd-run", "--user", "--scope", "--quiet",
            "-p", "MemoryMax=%d" % cap,
            "-p", "MemorySwapMax=%d" % SCOPE_SWAP_MAX,
            sys.executable, os.path.abspath(__file__), *sys.argv[1:]])
    except OSError:             # exec failed: run unscoped rather than not at all
        os.environ.pop("TESTMGR_SCOPED", None)
        print("testmgr: scope failed, running unscoped", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tier", choices=sorted(TIERS))
    ap.add_argument("--bench", action="store_true",
                    help="tracked benchmark run: fixed suite at -O0/-O2/-O3, "
                         "canary-checked then timed, rows appended to "
                         "tstate/bench.tsv (serial, ~2-3 min)")
    ap.add_argument("--jobs", type=int, help="fixed concurrency cap (else adaptive)")
    ap.add_argument("--serial", action="store_true", help="PAR=1: one job at a time")
    ap.add_argument("--fail-fast", action="store_true",
                    help="first red kills the run (inner-loop mode)")
    ap.add_argument("--deadline", type=float, default=3600,
                    help="global wall-clock budget, seconds (default 3600)")
    ap.add_argument("--list", action="store_true", help="print job table and exit")
    ap.add_argument("--job", metavar="GLOB",
                    help="run only jobs whose name matches (fnmatch), or "
                         "'src:<path>' to select by SOURCE FILE — stable across "
                         "renumbering, unlike target#NN; lets a watcher bisect "
                         "one failing job in isolation")
    ap.add_argument("--report-json", metavar="PATH",
                    help="write machine-readable per-job results (twatch)")
    ap.add_argument("--inject-hang", action="store_true",
                    help="add a sleep-loop job to prove hang handling")
    args = ap.parse_args()

    if args.bench:
        # deliberately unscoped: --bench appends to the tracked timing series in
        # tstate/bench.tsv, and it is serial, so it was never the thing that ate
        # the box.  Don't perturb a history that spans hundreds of rows.
        return run_bench()
    if not args.tier:
        ap.error("--tier is required (unless --bench)")

    # --list does no work; TESTMGR_NO_SCOPE=1 is the escape hatch (self-tests)
    if not args.list and os.environ.get("TESTMGR_NO_SCOPE") != "1":
        reexec_scoped()         # does not return if it scopes us

    build_compiler()
    jobs = generate(args.tier)
    if args.job:
        jobs = [j for j in jobs if job_selected(j, args.job)]
        if not jobs:
            sys.exit("testmgr: no jobs match --job %r" % args.job)
        for j in jobs:      # deps may have been filtered out: drop them
            j.deps = [d for d in j.deps if d in jobs]

    # the FPC canary skips (not fails) where FPC isn't installed — the watcher
    # box need not have it, exactly like an unfetched corpus tree
    if not shutil.which(FPC_BIN):
        for j in jobs:
            if j.target == "fpc-bootstrap":
                j.status = "skip"
    # self-skip jobs whose corpus tree is absent (twatch-setup contract:
    # "corpus jobs self-skip"); recipes with their own guard never get here
    absent, nabsent = {}, 0
    for j in jobs:
        missing = sorted({m for m in CORPUS_RE.findall("\n".join(j.lines))
                          if not os.path.isdir(
                              os.path.join(REPO, "library_candidates", m))})
        if missing:
            j.status = "skip"
            nabsent += 1
            for m in missing:
                absent[m] = absent.get(m, 0) + 1
    # A skipped corpus job is INVISIBLE in a green verdict — the run looks just
    # as green as one that actually ran it.  That is how the i386/arm32/riscv32
    # c-conformance reds hid on a box without c-testsuite.  So say it loudly,
    # up front, with the one command that fixes it.
    if absent:
        print(corpus_warning(absent, nabsent), flush=True)
    for j in jobs:
        j.deps = [d for d in j.deps if d.status != "skip"]
    if args.inject_hang:
        hang = Job("injected-hang", 0, ["while :; do :; done"])
        hang.cls = "unit"
        hang.timeout = 10       # small: prove the per-job timeout kill path
        jobs.append(hang)

    if args.list:
        for j in jobs:
            print("%-32s %-12s %2d lines  %s%s" %
                  (j.name, j.cls, len(j.lines), j.src,
                   "  deps:" + ",".join(d.name for d in j.deps) if j.deps else ""))
        print("total: %d jobs" % len(jobs))
        return 0

    os.makedirs(RUN_TMP, exist_ok=True)
    scale = calibrate()
    # propagate to child scripts with their own inner `timeout` calls
    os.environ["TESTMGR_TIME_SCALE"] = "%.2f" % scale
    os.environ["TESTMGR_TMP"] = RUN_TMP     # for tool scripts' own scratch
    logdir = tempfile.mkdtemp(prefix="testmgr-")
    run_jobs = [j for j in jobs if j.status != "skip"]
    mgr = Manager(run_jobs, args, scale, logdir)
    nskip = len(jobs) - len(run_jobs)
    print("testmgr: tier=%s jobs=%d%s cap=%d scale=%.2f logs=%s"
          % (args.tier, len(run_jobs),
             " skip=%d(corpus-absent)" % nskip if nskip else "",
             mgr.hard_cap, scale, logdir), flush=True)
    t0 = time.monotonic()
    rc = mgr.run()
    wall = time.monotonic() - t0
    save_metrics(mgr.metrics)
    write_json_atomic(LIVE_PATH, {
        "ts": time.time(), "tier": args.tier, "pct": 100.0,
        "done": mgr.done_count(), "total": len(mgr.jobs),
        "elapsed": round(wall, 1), "eta": 0, "running": [],
        "red": [j.name for j in jobs if j.status in ("fail", "timeout")],
        "verdict": "GREEN" if rc == 0 else
                   "INTERRUPTED" if rc == 130 else "RED"})

    # ---- deterministic fixed-order report ----
    print("\n== testmgr report (tier %s, %.1fs wall) ==" % (args.tier, wall))
    first_fail = None
    slow = []
    for j in jobs:                       # generation order == report order
        dur = (j.t1 - j.t0) if j.t0 and j.t1 else 0.0
        note = ""
        if j.exp_dur and j.status == "pass" and dur > max(5.0, j.exp_dur * 4):
            note = "  SLOW (expected %.1fs)" % j.exp_dur
            slow.append(j.name)
        # advisory reds are reported, but they are a NOTICE for the owning
        # track — not part of the gate, and not "the first failure"
        state = ("NOTICE" if j.advisory and j.status != "pass"
                 else j.status.upper())
        print("  %-8s %-32s %-12s %6.1fs  %s%s" %
              (state, j.name, j.cls, dur, j.src, note))
        if j.status in ("fail", "timeout") and not j.advisory \
                and first_fail is None:
            first_fail = j
    npass = sum(1 for j in jobs if j.status == "pass")
    print("  %d/%d pass%s" % (npass, len(jobs) - nskip,
                              ", %d skip (corpus absent)" % nskip if nskip else ""))
    # repeat the banner at the END too: on a 1000-job run the startup one has
    # long scrolled away, and this is the line someone reads before believing
    # a GREEN
    if absent:
        print(corpus_warning(absent, nabsent))
    if first_fail:
        print("\n-- first failure: %s (%s)%s --" %
              (first_fail.name, first_fail.status,
               " — " + first_fail.src if first_fail.src else ""))
        print("-- commands --")
        for ln in first_fail.lines:
            print("  " + ln)
        if first_fail.logpath and os.path.exists(first_fail.logpath):
            print("-- log (%s) --" % first_fail.logpath)
            with open(first_fail.logpath, errors="replace") as f:
                sys.stdout.write(f.read())
    print("\ntestmgr: %s" % ("GREEN" if rc == 0 else
                             "INTERRUPTED" if rc == 130 else "RED"))
    if args.report_json:
        rep = {"tier": args.tier, "wall": round(wall, 1), "scale": round(scale, 2),
               "verdict": "GREEN" if rc == 0 else "RED",
               "slow": slow,
               # "sel": the STABLE way to name this job again later (twatch
               # bisects and files tickets on it).  j.name is a positional
               # index that renumbers whenever a test is inserted above it.
               "jobs": [{"name": j.name, "cls": j.cls, "src": j.src,
                         "sel": j.sel or j.name,
                         "advisory": j.advisory,
                         "status": j.status,
                         "dur": round((j.t1 - j.t0), 1) if j.t0 and j.t1 else 0.0,
                         "mem": j.peak_rss, "cpu": round(j.cpu_sec, 1),
                         "log": j.logpath}
                        for j in jobs]}
        with open(args.report_json, "w") as f:
            json.dump(rep, f, indent=1)
    return rc


if __name__ == "__main__":
    sys.exit(main())
