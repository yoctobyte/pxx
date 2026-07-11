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
MEM_FLOOR = 1500 << 20          # never admit below this MemAvailable
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
        parts = ["cd %s || exit 1" % shlex.quote(REPO)]
        for ln in self.lines:
            if ln.strip().startswith("#"):
                continue                      # recipe comment: shell no-op
            parts.append("{\n%s\n} || exit $?" % ln.replace("/tmp/", RUN_TMP + "/"))
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
    tmp_re = re.compile(r"/tmp/[A-Za-z0-9_./+-]+")
    parent = list(range(len(groups)))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    owner = {}
    for i, g in enumerate(groups):
        for f in set(tmp_re.findall("\n".join(g))):
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
    return jobs


# -------------------------------------------------------------- sampling ---
def mem_available():
    with open("/proc/meminfo") as f:
        for ln in f:
            if ln.startswith("MemAvailable:"):
                return int(ln.split()[1]) << 10
    return 0


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
        mem = job.peak_rss if job.peak_rss > 0 else (32 << 20)
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
        # charge est_mem for jobs too young for their RSS to show up yet
        uncharged = sum(j.est_mem
                        for j in self.running if now - j.t0 < 5.0)
        avail = mem_available() - uncharged
        return avail - job.est_mem > MEM_FLOOR

    def deps_ready(self, job):
        for d in job.deps:
            if d.status == "queued" or d.status == "running":
                return None
            if d.status != "pass":
                return False
        return True

    def watchdog(self):
        if mem_available() >= (MEM_FLOOR >> 1):
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
            print("testmgr: memory pressure — killed %s, requeued" % newest.name,
                  flush=True)

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
                print("  [%4d/%d] %-7s %-28s %6.1fs" %
                      (self.done_count(), len(self.jobs), mark, job.name, dur),
                      flush=True)
                if job.status != "pass":
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
# (name, source, canary argv, timed argv) — canary mode must be
# deterministic; {tmp} expands to the bench scratch dir
BENCH_SUITE = (
    ("mandelbrot", "examples/mandelbrot/mandelbrot.pas",
     [], ["--bench", "400", "300"]),               # float compute
    ("raytracer", "examples/raytracer/raytracer.pas",
     [], ["--ppm", "{tmp}/rt.ppm", "480", "360"]),  # call-heavy float
    ("sieve", "examples/primes/sieve.pas", [], []),  # memory-bound int
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

    for name, src, canary, timed in BENCH_SUITE:
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
                    help="run only jobs whose name matches (fnmatch); "
                         "lets a watcher bisect one failing job in isolation")
    ap.add_argument("--report-json", metavar="PATH",
                    help="write machine-readable per-job results (twatch)")
    ap.add_argument("--inject-hang", action="store_true",
                    help="add a sleep-loop job to prove hang handling")
    args = ap.parse_args()

    if args.bench:
        return run_bench()
    if not args.tier:
        ap.error("--tier is required (unless --bench)")

    build_compiler()
    jobs = generate(args.tier)
    if args.job:
        jobs = [j for j in jobs if fnmatch.fnmatch(j.name, args.job)]
        if not jobs:
            sys.exit("testmgr: no jobs match --job %r" % args.job)
        for j in jobs:      # deps may have been filtered out: drop them
            j.deps = [d for d in j.deps if d in jobs]

    # self-skip jobs whose corpus tree is absent (twatch-setup contract:
    # "corpus jobs self-skip"); recipes with their own guard never get here
    for j in jobs:
        missing = sorted({m for m in CORPUS_RE.findall("\n".join(j.lines))
                          if not os.path.isdir(
                              os.path.join(REPO, "library_candidates", m))})
        if missing:
            j.status = "skip"
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
        print("  %-8s %-32s %-12s %6.1fs  %s%s" %
              (j.status.upper(), j.name, j.cls, dur, j.src, note))
        if j.status in ("fail", "timeout") and first_fail is None:
            first_fail = j
    npass = sum(1 for j in jobs if j.status == "pass")
    print("  %d/%d pass%s" % (npass, len(jobs) - nskip,
                              ", %d skip (corpus absent)" % nskip if nskip else ""))
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
               "jobs": [{"name": j.name, "cls": j.cls, "src": j.src,
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
