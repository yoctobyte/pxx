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
import atexit
import filecmp
import fnmatch
import hashlib
import glob
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Stable, unique per CLONE (not per run): build outputs must not collide with a
# testmgr running in another checkout on the same box, but must still be reused
# across runs in THIS checkout (make's incrementality depends on it).
REPO_TAG = re.sub(r"[^A-Za-z0-9_-]", "-", REPO.strip("/"))[-40:]
COMPILER = os.environ.get("TESTMGR_COMPILER", "compiler/pascal26")

# ---------------------------------------------------------------- tiers ----
# Targets per tier, in REPORT order.  quick = inner loop; limited = quick +
# self-host fixedpoint chain (test-smoke prints both) + the native gate +
# C conformance; full = everything: cross targets + corpus.  Serial `make
# test` = test-core test-threads test-asm test-debug-g lib-fpc-clean.
TIERS = {
    "quick": ["test-quick"],
    # test-nilpy: MAINLINE and gated (CLAUDE.md puts Track N as a peer of C),
    # but it was in no tier at all — so 238 of the 309 .npy files the Makefile
    # compiles were invisible to the watcher and `make test-nilpy` could be RED
    # while the full tier reported GREEN (measured 2026-08-01).
    #
    # It sits in limited/full, NOT native. Enrolling all ~300 jobs at native
    # took the fast verdict from ~104s to ~235s — and native is the tier dev
    # boxes gate their pushes on, so that is the one number T must not inflate.
    # The fast NilPy signal instead comes from the quick-tier canary
    # (test/quick_canary_nilpy.npy, feature-t-quick-canary-for-nilpy-and-c):
    # broad-not-deep, ~1s, catches gross breakage. Coverage stays here.
    "native": [            # fast watcher verdict: all native, no qemu/
        "test-smoke",      # corpus/conformance — cross runs in the full
        "test-core", "test-threads", "test-asm", "test-debug-g",   # backfill
        "lib-fpc-clean",
    ],
    # test-uforth: same hole test-nilpy was in, found 2026-08-08 —
    # `grep -c uforth tools/testmgr.py` was 0, so the densest NilPy regression
    # signal in the tree (~4300 lines of unmodified Python + a layered .UFO
    # stdlib, differential against CPython) was protected only by somebody
    # remembering to type `make test-uforth`. limited+full, NOT native: it is
    # ~46 s and native is the tier dev boxes gate their pushes on. Placement
    # matches test-nilpy for the same reason.
    # TIER 1 — native depth, ALL frontends, no qemu.
    #
    # The hunt is two-dimensional: test cases x platforms. Both axes cost, and
    # they are NOT equally valuable — native depth pays more per minute right
    # now, so it must be runnable WITHOUT paying for platform breadth
    # (task-t-pin-fast-track-t-owns-verification, deliverable 2).
    #
    # `limited` already meant "the tier for a box that cannot run qemu"
    # (devdocs/dev/track-t.md), so this deepens that meaning rather than
    # changing it: the native corpus subjects — real programs, the densest
    # signal there is — used to appear ONLY in `full`, behind twelve cross
    # targets. Depth therefore cost breadth's price, and got run at breadth's
    # cadence.
    #
    # NilPy is tier 1 deliberately, not an afterthought: it is a first-class
    # frontend whose bugs cluster (one fix routinely uncovers the next), so a
    # full native NilPy run pays for itself on nearly every cycle.
    #
    # And a byte-identical self-host proves only that the compiler reproduces
    # itself through the paths IT exercises. A codegen bug in a construct
    # compiler.pas never uses is invisible to that gate forever — which is the
    # whole reason a heavier native tier is worth running past a green pin.
    "limited": [
        "test-smoke",          # test-quick + self-host byte-identity chain
        "test-core", "test-threads", "test-asm", "test-debug-g",
        "test-nilpy", "test-uforth",
        "lib-fpc-clean",
        "test-c-conformance",
        # NOT test-float-determinism: it drives examples/mandelbrot through
        # tools/run_target.sh, so it classes `qemu` and would break the one
        # property `limited` promises — that a box with no qemu can run it.
        # It stays in full.
        "test-emit-obj",
        # the real-program corpus, native only — the cross variants stay in full
        "test-lua", "test-cjson", "test-zlib",
        "test-sqlite-threads-x86_64",
    ],
    # TIER 2 — everything in tier 1, PLUS platform breadth under qemu. An order
    # of magnitude slower, so it runs less often; a cross-only red is an
    # ordinary ticket, while a tier-1 red is what the tracks are building on.
    "full": [
        "test-smoke",
        "test-core", "test-threads", "test-asm", "test-debug-g",
        "test-nilpy", "test-uforth",
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
OPT_SHARDS = 12
# A CONSTANT, deliberately not derived from os.cpu_count(). The shard index is
# part of the job name, and tstate is SHARED between hosts — a 12-core box
# publishing `optdiff#shard0/12` while a 4-core box publishes `optdiff#shard0/6`
# would make every cross-host comparison meaningless and manufacture NEW-RED /
# FIXED pairs on every handover.
#
# Raised 6 -> 12 on 2026-08-01. The opt tier was structurally capped at 6-way
# parallelism on a 12-core box: measured 1483s of work, wall 281s, and the wall
# EQUALLED the longest single shard (280.6s) — scheduling was already optimal,
# there was simply nothing else to run. Twelve shards halve the critical path.
#
# Changing this reshuffles every program's shard (unavoidable for any pure
# function of the name), which renames jobs. Done while the matrix was 100%
# green, so no red migrated and no phantom NEW-RED/FIXED pair was produced.
# Do the same next time.

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
# Runtime-nondeterministic classes: they RUN a program whose scheduling/socket/
# thread timing can flake under a loaded full-matrix run (asyncecho = qemu,
# sqlite-threads = qemu, optdiff = opt, threaded sqlite/lua = corpus, sharded
# conformance = conformance).  A single transient nonzero exit or timeout in
# these is NOT a regression — it produces a 0-in-range false NEW-RED in tstate
# that self-clears next tick.  So re-run a FAILED job in these classes before
# calling it RED (the bench path already does this for lost samples via
# BENCH_EXTRA_TRIES).  Deterministic classes — `unit` (build+run of a fixed
# program) and `selfhost` (build + byte-identical fixedpoint, where a flake is a
# genuine nondeterminism bug to reseed, not retry) — stay SINGLE-SHOT.  A real
# red fails every attempt, so confirm-retry never hides one; it only costs
# re-runs on the already-failing minority.  See
# bug-t-flaky-async-multithreaded-tests-false-newred.
RUN_RETRY_CLASSES = frozenset({"qemu", "corpus", "conformance", "opt"})
RUN_RETRY_TRIES = 3      # total attempts before a fail/timeout is final
# Failure signatures that are retriable in ANY class, including the single-shot
# ones above.  Scoped to signatures that provably say nothing about the binary's
# CONTENTS, so this cannot mask what single-shot exists to catch.
#
# ETXTBSY: the kernel refuses to exec a file some process still holds open for
# writing (classic mechanism: A opens the binary for writing, B forks and
# inherits the fd, A closes but B still holds it).  Observed 2026-08-02 on
# test-core@1 and again on test-smoke, both times AFTER the compile reported
# `ok:` — nothing was miscompiled, and the same job passes on re-run.  A real
# fixedpoint mismatch or genuine nondeterminism fails EVERY attempt, so a
# signature-scoped retry cannot hide one; a blanket selfhost retry would, which
# is why that stays forbidden.  Root cause belongs in the recipe (write under a
# temp name and rename into place, atomic on one filesystem) —
# bug-t-etxtbsy-race-reds-single-shot-selfhost-jobs.
RUN_RETRY_SIGNATURES = ("Text file busy", "ETXTBSY")
RUN_RETRY_SIG_TAIL = 8192   # bytes of the log tail to scan for a signature
# ---- co-tenancy: another testmgr, from another CLONE, on the same box -------
# The run lock is per-repo (.testmgr/run.lock), so it cannot see a run in a
# different checkout — and the watcher daemon lives in its own dedicated clone
# by design. Two testmgrs then each size their parallelism to the WHOLE box and
# together oversubscribe it ~2x. The jobs that lose are the long ones, and they
# lose by being KILLED, not by answering wrongly: the tell is `Terminated` in
# the log with the compile line reading `ok:`.
#
# That killed a 111.5s test-core job at e584d7b4 and published it as NEW-RED.
# The job passes standalone and the dev session's own run at the same tree
# called it "flaky (recovered on retry)" — the same job, two verdicts, decided
# by who else was on the box. Worse, the job was
# test_interface_mainbody_ascast_temp: the as-cast temp lifetime landmine is a
# REAL known bug, so a false red there reads exactly like it resurfacing and
# pulls a dev session into a full investigation.
# bug-t-watcher-dev-contention-false-newred.
#
# A kill under co-tenancy says nothing about the binary's CONTENTS — the same
# reasoning that makes the ETXTBSY signature safe to retry in single-shot
# classes — so it is retried in ANY class, but ONLY while a peer is actually
# present. On an idle box every one of these paths is a no-op and single-shot
# stays single-shot.
PEER_POLL_PERIOD = 15.0     # seconds between /proc scans for co-tenant runs
PEER_TIME_FACTOR = 2.0      # two runs sizing to the whole box ~halve our share
CONTENTION_SIGNALS = (signal.SIGTERM, signal.SIGKILL, signal.SIGHUP)
# tiers that carry the FPC cold-start canary (advisory; see fpc_canary_job).
# Not "quick": that is the inner loop and an FPC compile of compiler.pas is a
# whole build, not an inner-loop cost.
FPC_CANARY_TIERS = ("native", "limited", "full")
# Tiers carrying the self-host fixedpoint GATE (~20s: two compiler builds).
# Not "quick": that is the inner loop, and this is a bootstrap chain. It is NOT
# advisory — byte-identical self-host is the gate the stable binary rests on.
SELFHOST_GATE_TIERS = ("native", "limited", "full")
# The job whose red aborts the tier and publishes immediately (see Manager.run).
SELFHOST_GATE_TARGET = "selfhost-fixedpoint"
FPC_CANARY_TARGET = "fpc-bootstrap"
MEM_FLOOR = 1500 << 20          # never admit below this MemAvailable
SWAP_FLOOR = 1000 << 20         # never admit with less free swap than this...
SWAP_FLOOR_FRAC = 0.10          # ...but never demand more than this much of SwapTotal
PSI_ADMIT = 20.0                # never admit above this memory PSI (some avg10)
PSI_QUIET = 1.0                 # below this the box is demonstrably not stalling
SWAP_GATE_AVAIL = 3 * MEM_FLOOR  # ...and with this much MemAvailable, free swap
                                # is stale desktop pages, not memory pressure
PSI_KILL = 45.0                 # kill+requeue the newest job above this PSI
SCOPE_MAX_FRAC = 0.60           # cgroup MemoryMax = this * MemTotal ...
SCOPE_MIN_ABS = 8 << 30         # ... with 8G as a FLOOR, not a ceiling.
# This was `min(8G, frac*MemTotal)`, i.e. 8G was an absolute CEILING. On borg
# (15G) that was indistinguishable from the fraction, so it never showed. On
# xeon (60G) it capped the run at 8G — 13% of the box — while the fraction
# would have allowed 36G, and the 13 heaviest jobs alone sum to ~15.5G. The
# consequence is not slowness but a mystery red: the kernel OOM-kills a job
# INSIDE our own cgroup while 54G sits free, and a killed job looks like a
# failed one. The fraction already does the "don't be greedy" job the absolute
# was there for; the absolute now only protects small boxes from too tight a
# budget, and never exceeds 75% of RAM on one.
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


def metrics_key(job):
    """Identity of a job's learned metrics ACROSS commits.

    job.sel, never job.name -- for the same reason twatch's job_key() exists:
    `test-core#120` is a POSITIONAL index into the target's recipe lines, so
    inserting one test renumbers every job after it. Keyed positionally, the
    EWMA silently blends measurements from whatever different tests have
    occupied that slot over time.

    Observed 2026-07-20: test-core#120 (a 36-line interface test whose binary
    is 36 KB) carried dur=88.65s / mem=6.77GB over n=861 -- inherited from
    heavier tests that previously held slot #120. The scheduler then refused
    to admit it (avail - est_mem fell under MEM_FLOOR), starved, and forced
    the whole run through serially in degraded mode.
    """
    return job.sel or job.name


METRICS_VERSION = 2             # 2: keyed by job.sel, not recipe position
METRICS_VERSION_KEY = "_version"


def _positional(k):
    """Legacy key: `<target>#<digits>`, i.e. keyed by recipe position."""
    _, _, tail = k.rpartition("#")
    return tail.isdigit()


def load_metrics():
    try:
        with open(METRICS_PATH) as f:
            m = json.load(f)
    except (OSError, ValueError):
        return {}
    if m.pop(METRICS_VERSION_KEY, 1) >= METRICS_VERSION:
        return m
    # ONE-TIME migration off position-keyed metrics. Drop rather than convert:
    # a blended average cannot be attributed back to the tests that produced
    # it, so the data is unusable, not merely mis-keyed.
    #
    # Gated on the version marker, NOT on key shape, because shape alone
    # cannot tell the two cases apart: job_selector() legitimately falls back
    # to the positional name for jobs that compile no source (test-core#00,
    # lib-fpc-clean#00), so for THOSE jobs the positional key IS the stable
    # selector. Purging by shape every load deleted their metrics forever --
    # they could never reach METRICS_MIN_RUNS and were stuck on class
    # defaults, which is the churn this replaces.
    stale = [k for k in m if _positional(k)]
    for k in stale:
        del m[k]
    if stale:
        print("testmgr: migrated metrics to v%d — dropped %d position-keyed "
              "entries (re-learning per stable selector)"
              % (METRICS_VERSION, len(stale)), flush=True)
    return m


def save_metrics(m):
    os.makedirs(os.path.dirname(METRICS_PATH), exist_ok=True)
    tmp = METRICS_PATH + ".tmp"
    # stamp the schema version so the v1->v2 purge runs exactly once; without
    # it every load would re-purge and the position-keyed-by-design jobs
    # (test-core#00 et al) could never accumulate runs
    with open(tmp, "w") as f:
        json.dump(dict(m, **{METRICS_VERSION_KEY: METRICS_VERSION}), f,
                  indent=1, sort_keys=True)
    os.replace(tmp, METRICS_PATH)


LIVE_PATH = os.path.join(REPO, ".testmgr", "live.json")
LOCK_PATH = os.path.join(REPO, ".testmgr", "run.lock")
# How long the scheduler may make NO progress (nothing running, nothing
# admitted) before it forces a job through the memory gates. See admit_forced().
STARVE_GRACE = 90.0
# A lock whose heartbeat is older than this is dead, whatever its pid says: a
# SIGKILLed run leaves the file behind, and a stale lock that blocks every
# future run is exactly as bad as no lock at all.
HEARTBEAT_STALE = 120.0
HEARTBEAT_PERIOD = 10.0         # beat interval; must be << HEARTBEAT_STALE
# default work-weights for jobs with no learned duration yet, per class —
# used only for the progress estimate, never for scheduling
CLASS_WEIGHT = {"unit": 1.0, "qemu": 2.0, "selfhost": 60.0,
                "corpus": 45.0, "conformance": 90.0, "opt": 30.0}


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def find_runs():
    """Every testmgr on this box, whatever clone it belongs to. [(pid, repo, tier, age)]

    You cannot find these with pstree, and that is the point. reexec_scoped()
    re-execs testmgr inside a transient systemd scope (that is what applies the
    memory cap), so systemd ADOPTS it: PPID becomes 1, it leaves the launching
    shell's process tree, and it is not a job of that shell. Consequences:

      * a running testmgr is invisible to `pstree` / `jobs` -- it looks like
        nothing is happening;
      * killing the shell, or the agent session, does NOT kill it. It runs on,
        detached, until its global deadline.

    So orphans accumulate silently across sessions, and every orphan holds memory,
    which raises PSI, which makes NEW runs fail admission -- see admit_forced().
    The orphans are the cause; the starvation was only the symptom. A per-repo
    lock cannot see them (they are in other clones), so discovery has to be
    box-wide, by scanning /proc.
    """
    out = []
    me = os.getpid()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == me:
            continue
        try:
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                argv = f.read().decode("utf-8", "replace").split("\0")
        except OSError:
            continue
        path = next((a for a in argv if a.endswith("testmgr.py")), None)
        if not path:
            continue
        # A process that merely CARRIES the command line is not a run: `timeout
        # 600 python3 tools/testmgr.py`, `bash -c "...testmgr.py..."`, gate.sh,
        # and systemd-run itself all match the argv scan. Counting them
        # inflated --status and, once co-tenancy started steering retries,
        # would have made a solo run believe it was contended — the run's own
        # `timeout` wrapper posing as its rival.
        try:
            exe = os.path.basename(os.path.realpath("/proc/%s/exe" % pid))
        except OSError:         # another user's process, or already gone
            continue
        if not exe.startswith("python"):
            continue
        tier = "?"
        for i, a in enumerate(argv):
            if a == "--tier" and i + 1 < len(argv):
                tier = argv[i + 1]
        # argv may hold a RELATIVE path (`tools/testmgr.py`), which resolves
        # against THAT process's cwd, not ours. Getting this wrong yields an
        # empty repo, which compares equal to no clone and unequal to ours.
        if not os.path.isabs(path):
            try:
                path = os.path.join(os.readlink("/proc/%s/cwd" % pid), path)
            except OSError:
                continue
        repo = os.path.dirname(os.path.dirname(os.path.realpath(path)))
        try:
            age = time.time() - os.path.getmtime("/proc/%s" % pid)
        except OSError:
            age = 0.0
        out.append((int(pid), repo, tier, age))
    return sorted(out)


def foreign_runs():
    """Runs belonging to a DIFFERENT clone on this box — our co-tenants.

    A run in our own repo is already excluded by the per-repo lock, so anything
    left is exactly what that lock cannot see: the watcher daemon's dedicated
    clone versus a dev checkout, or vice versa (see CONTENTION_SIGNALS).
    """
    return [r for r in find_runs() if r[1] != REPO]


def read_lock():
    try:
        with open(LOCK_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def lock_state():
    """(state, info) where state is 'free' | 'live' | 'stale'.

    Liveness needs BOTH a live pid and a fresh heartbeat. A pid alone is not
    enough: pids get reused, and a wedged run that stopped heartbeating is not
    something a new run should defer to forever. A heartbeat alone is not enough
    either -- it could be a file nobody is updating.
    """
    info = read_lock()
    if not info:
        return "free", None
    age = time.time() - info.get("heartbeat", 0)
    if pid_alive(info.get("pid", -1)) and age < HEARTBEAT_STALE:
        return "live", info
    return "stale", info


def kill_run(pid, why):
    """Kill a wedged/superseded testmgr, WITHOUT killing the caller.

    Nor the caller's PARENT. `--pin` holds the repo lock for the whole pin and
    runs the gate as a child; that child reaching a kill path here means it is
    about to SIGKILL the pin that spawned it (exit 137, nothing pinned —
    bug-t-testmgr-pin-force-kills-its-own-parent). The lock-inheritance path in
    acquire_lock() is what makes the child never GET here; this is the backstop
    for whatever else learns to call kill_run. Weak after reexec_scoped() —
    systemd adopts the run, so getppid() becomes 1 — hence backstop, not fix.

    Group-killing is what we want -- a testmgr that dies leaving orphaned qemu
    or compiler children behind is half the reason the box gets starved in the
    first place. But `killpg(getpgid(pid))` is a loaded gun: if that process
    shares our process group (testmgr started plainly from a shell, no setsid),
    the group is the SHELL's, and group-killing it takes down the shell, this
    agent session, and every sibling job. The first run of this test SIGKILLed
    itself proving exactly that.

    So group-kill only a process that leads its own group (a scoped testmgr
    does -- see reexec_scoped/setsid), never our own group, and otherwise fall
    back to killing the single pid.
    """
    if not pid_alive(pid):
        return
    if pid in (os.getpid(), os.getppid()):
        print("testmgr: refusing to kill pid %d (%s) — it is us or our parent"
              % (pid, why), file=sys.stderr, flush=True)
        return
    try:
        pgid = os.getpgid(pid)
    except OSError:
        return
    try:
        if pgid == pid and pgid != os.getpgid(0):
            os.killpg(pgid, signal.SIGKILL)     # leader of its own group: safe
        else:
            os.kill(pid, signal.SIGKILL)        # shares our group: pid only
        print("testmgr: killed run pid %d — %s" % (pid, why), flush=True)
    except OSError:
        pass


def reap_stale(info):
    """Clean up after a run that died without releasing its lock."""
    pid = info.get("pid", -1)
    kill_run(pid, "wedged (no heartbeat for >%ds)" % HEARTBEAT_STALE)
    scratch = "/tmp/testmgr-scratch-%d" % pid
    if os.path.isdir(scratch):
        shutil.rmtree(scratch, ignore_errors=True)
    try:
        os.unlink(LOCK_PATH)
    except OSError:
        pass


def file_sha256(path):
    """Strong hash of a file, or None if it is not there / not readable."""
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None


def snapshot_compiler():
    """Copy the compiler into the run's scratch and return (path, sha256).

    Returns (None, None) if it cannot be taken, in which case jobs fall back to
    the repo path unchanged — a missing snapshot must never fail a run.
    """
    src = os.path.join(REPO, "compiler/pascal26")
    if not os.path.exists(src):
        return None, None
    try:
        os.makedirs(RUN_TMP, exist_ok=True)
        shutil.copy2(src, RUN_COMPILER)     # copy, deliberately: see RUN_COMPILER
    except OSError as e:
        print("testmgr: could not snapshot the compiler (%s) — running against "
              "the repo path; a concurrent rebuild can still corrupt this run" % e,
              flush=True)
        return None, None
    return RUN_COMPILER, file_sha256(RUN_COMPILER)


def drop_run_tmp():
    """Remove THIS run's scratch dir. Registered atexit — see sweep_orphan_tmp.

    Safe to delete on exit: RUN_TMP holds built test binaries, not the per-job
    logs a report points at (those live in `logdir`, kept deliberately).
    """
    shutil.rmtree(RUN_TMP, ignore_errors=True)


def sweep_orphan_tmp():
    """Reclaim scratch dirs belonging to runs that no longer exist.

    Cleanup previously existed ONLY on the abnormal path: reap_stale() removes
    a scratch dir, but only when a *live* run notices a wedged predecessor
    through the lock file. A normal exit released the lock and left its
    ~375 MB scratch dir behind forever.

    That is not a slow leak on a watcher box. `/tmp` on xeon is a **31 GB
    tmpfs — RAM** — and the daemon starts a run every cycle: 7.3 GB
    accumulated in under three hours (2026-07-31), on track to exhaust the
    whole tmpfs overnight and to compete for the very memory testmgr's
    scheduler packs jobs against. A full /tmp then fails jobs that are
    perfectly healthy, i.e. it manufactures reds.

    Liveness is the pid in the directory name: if the process is gone the dir
    is garbage, whoever created it and however it died (including SIGKILL and
    power cuts, which no atexit can cover).
    """
    # (a) pid-suffixed dirs: liveness is the pid, so this also reclaims what a
    # SIGKILL left behind — and SIGKILL is routine here, because testmgr kills
    # its own over-budget jobs, which is exactly why the EXIT trap inside
    # run_c_conformance.sh cannot be relied on (a trap never runs on SIGKILL).
    for pat, sep in (("/tmp/testmgr-scratch-*", "-"),
                     ("/tmp/pxx_c_conformance.*", "."),
                     # the self-host build's per-invocation root (Makefile
                     # PXX_TMP); pid-keyed for exactly this reason
                     ("/tmp/pxx-build-*", "-")):
        for p in glob.glob(pat):
            try:
                pid = int(p.rsplit(sep, 1)[1])
            except (ValueError, IndexError):
                continue                  # not ours / not pid-suffixed
            if pid == os.getpid():
                continue
            try:
                os.kill(pid, 0)           # alive: leave it strictly alone
            except ProcessLookupError:
                shutil.rmtree(p, ignore_errors=True)
            except PermissionError:
                pass                      # another user's live run

    # (b) age-reaped dirs from the ENDLESS idle paths (bench/fuzz rounds). These
    # carry no pid, and on a box left running overnight they are monotonic:
    # ~130 MB/hour measured on xeon. Own cleanup landed alongside this, so the
    # sweep is the backstop for rounds killed mid-flight.
    now = time.time()
    for pat, keep in (("/tmp/tbench-*", IDLE_KEEP_SECS),
                      ("/tmp/pasmith.*", IDLE_KEEP_SECS),
                      ("/tmp/pasmith-check.*", IDLE_KEEP_SECS)):
        for p in glob.glob(pat):
            try:
                if os.path.isdir(p) and now - os.path.getmtime(p) > keep:
                    shutil.rmtree(p, ignore_errors=True)
            except OSError:
                pass

    # (c) Per-job log dirs are KEPT (reports cite their paths) but bounded both
    # ways: by age, and by count, so a busy night cannot accumulate unboundedly
    # inside the age window (128 dirs / 392 MB observed in well under 24h).
    logdirs = []
    for p in glob.glob("/tmp/testmgr-*"):
        if p.startswith("/tmp/testmgr-scratch-"):
            continue
        try:
            if os.path.isdir(p):
                logdirs.append((os.path.getmtime(p), p))
        except OSError:
            pass
    logdirs.sort(reverse=True)                       # newest first
    cutoff = now - LOGDIR_KEEP_SECS
    for i, (mtime, p) in enumerate(logdirs):
        if i >= LOGDIR_KEEP_MAX or mtime < cutoff:
            shutil.rmtree(p, ignore_errors=True)


def start_heartbeat(tier):
    """Beat from a daemon thread, for the WHOLE process lifetime.

    Not from the scheduler loop: build_compiler() and calibrate() run for
    minutes before the loop is even reached, and a heartbeat that only ticks
    while scheduling would go stale during a perfectly healthy build -- so a
    second run would declare us wedged and kill us mid-build. Liveness must mean
    "this process exists and is not frozen", which is a property of the process,
    not of one phase of it.
    """
    def beat():
        while True:
            info = read_lock()
            if not info or info.get("pid") != os.getpid():
                return          # someone force-took the lock: stop pretending
            info["heartbeat"] = time.time()
            info["tier"] = tier
            write_json_atomic(LOCK_PATH, info)
            time.sleep(HEARTBEAT_PERIOD)
    t = threading.Thread(target=beat, daemon=True)
    t.start()
    return t


def release_lock():
    """Drop the lock if it is still ours.

    Covers clean exit, exception and SIGINT/SIGTERM (atexit). It cannot cover
    SIGKILL or a power cut -- which is exactly why liveness is a HEARTBEAT and
    not merely the presence of this file: the stale path reclaims what this
    function never got to release.
    """
    info = read_lock()
    if info and info.get("pid") == os.getpid():
        try:
            os.unlink(LOCK_PATH)
        except OSError:
            pass


LOCK_INHERIT_ENV = "TESTMGR_LOCK_INHERITED"


def inherited_lock_owner():
    """The pid that holds the repo lock ON OUR BEHALF, if any.

    Set by run_pin() on the gate child it spawns. Survives reexec_scoped(),
    because that re-exec inherits os.environ -- the same property TESTMGR_SCOPED
    already relies on to avoid re-scoping forever.
    """
    try:
        pid = int(os.environ.get(LOCK_INHERIT_ENV, ""))
    except ValueError:
        return None
    return pid if pid > 0 else None


def acquire_lock(force):
    """Refuse to pile onto a live run; reclaim a dead one. Returns True if ours.

    Piling on is not harmless: admission is gated on GLOBAL machine memory, so a
    second run does not merely queue behind the first -- it competes with it,
    and both starve. "Re-running doesn't kill the old one" and "testmgr hangs"
    are the same bug seen from two ends.

    INHERITED LOCKS. `--pin` holds the lock for the whole pin -- gate included,
    deliberately, so nothing rebuilds compiler/pascal26 under stabilize-fast's
    feet -- and then runs the gate as a child of itself. That child must neither
    take the lock nor kill its holder: the holder is its own parent, and killing
    it is exit 137 with nothing pinned. `--force` meant "the lock you will find
    is mine, proceed"; it was implemented as "kill whoever holds it".

    So ownership is passed DOWN explicitly instead. The child does not acquire,
    does not release (release_lock already no-ops on a pid that is not ours) and
    does not heartbeat (start_heartbeat's beat loop returns for the same reason)
    -- the parent does all three for the whole window.
    """
    owner = inherited_lock_owner()
    if owner is not None:
        info = read_lock()
        if info and info.get("pid") == owner and pid_alive(owner):
            print("testmgr: using the repo lock held by pid %d (inherited)"
                  % owner, flush=True)
            return True
        # The lock we were promised is gone -- force-taken by a third run, or
        # its holder died. Refusing is right either way: the window this run was
        # supposed to be protected by no longer exists, and the alternative is
        # to start killing processes on behalf of a parent that may itself be
        # dead. The pin above us reports the gate rc and pins nothing.
        print("testmgr: the inherited lock (pid %d) is gone — refusing to "
              "take one of my own" % owner, file=sys.stderr)
        return False

    state, info = lock_state()
    if state == "live" and not force:
        ago = int(time.time() - info.get("started", time.time()))
        print("testmgr: a run is ALREADY LIVE (pid %d, tier %s, started %dm%02ds ago)"
              % (info.get("pid", -1), info.get("tier", "?"), ago // 60, ago % 60),
              file=sys.stderr)
        print("         Two runs compete for the same memory gates and starve each "
              "other.\n"
              "         Wait for it, or re-run with --force to kill it and take over.",
              file=sys.stderr)
        return False
    if state == "live" and force:
        print("testmgr: --force — killing the live run (pid %d) and taking over"
              % info.get("pid", -1), flush=True)
        kill_run(info.get("pid", -1), "superseded by --force")
        reap_stale(info)
    elif state == "stale":
        reap_stale(info)
    # Claim it NOW, not at the first scheduler tick. build_compiler() runs for
    # minutes before the loop starts, and a lock that does not exist yet is a
    # lock that does not work: a second run would sail straight through the
    # check and race us. That race is not merely wasteful -- both runs build
    # into the SAME fixed paths (/tmp/pascal26-build, -verify), so the self-host
    # fixedpoint job compares one run's binary against the other's and reports a
    # byte-1 difference. A FAKE self-host regression, on the very gate that
    # blesses the stable binary. Observed while testing this lock.
    write_json_atomic(LOCK_PATH, {
        "pid": os.getpid(), "tier": "?",
        "started": time.time(), "heartbeat": time.time()})
    return True


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
#
# The character class is a WHITELIST, not "anything but a separator". The old
# `[^/\s"']+` also accepted punctuation, so it matched the PROSE inside a shell
# SKIP message — `echo "stb_sprintf_probe: SKIP (no library_candidates/stb)"` —
# and extracted the corpus `stb)`. No such directory can ever exist, so the job
# self-skipped permanently on every host, fetched or not, and the remedy the
# warning printed (`install_lib_candidates.sh stb)`) was itself invalid.
# bug-t-corpus-regex-invents-phantom-tree.
CORPUS_RE = re.compile(r"library_candidates/([A-Za-z0-9_.+-]+)")
# A recipe line that tests for its own corpus path before using it handles the
# absence itself (prints SKIP, exits 0), so it must NOT drag the whole job into
# a skip: jobs bundle several sources, and the stb probe shared one with the
# b207 non-compound-switch/Duff's-device regression — a test with no corpus
# dependency at all, which consequently had not run on any watcher host since
# the probe was appended next to it.
CORPUS_GUARD_RE = re.compile(r"\[\s+-[a-z]\s+library_candidates/")

# private per-run substitute for the recipes' literal /tmp/ paths (see
# Job.script); created in main(), world-unreadable is not needed — /tmp
# hygiene only, the OS reaps it
RUN_TMP = "/tmp/testmgr-scratch-%d" % os.getpid()
# The run's OWN copy of the compiler. `compiler/pascal26` is a single mutable
# path and a prerequisite of every test target, so any unrelated make (a
# `make pxx-debug` for a gdb build, say) can replace it mid-run: observed
# 2026-08-01 nine minutes into a test-nilpy, earlier jobs on the old binary and
# later ones on the new. Jobs run against this snapshot instead, which makes a
# concurrent rebuild structurally harmless rather than a discipline problem —
# and makes provenance exact, since the run owns the bytes it tested.
#
# A COPY, not a hardlink. The hardlink trick needs the build to rename into
# place (new inode, old bytes kept alive by the link). Measured on this box it
# does NOT: `mv $(BUILD_COMPILER) $(COMPILER)` crosses from tmpfs to ext4, so
# coreutils falls back to copy+unlink and writes the EXISTING destination inode
# in place — inode 270865 before and after a real rebuild. A hardlink would
# therefore have tracked the rebuild instead of pinning the old bytes, and a
# reader can transiently see a half-written binary.
RUN_COMPILER = os.path.join(RUN_TMP, "pascal26")
# `./compiler/pascal26` but never `./compiler/pascal26-managed` / `-debug`.
COMPILER_PATH_RE = re.compile(r"\./compiler/pascal26(?![-\w])")
# How long a finished run's per-job log dir survives for post-mortem. Reports
# cite these paths, so they outlive the run — but not indefinitely (see
# sweep_orphan_tmp; /tmp is a tmpfs on the watcher box).
LOGDIR_KEEP_SECS = 24 * 3600
# ...and a hard cap on how many, so a busy night cannot fill /tmp inside the age
# window. Newest kept; a report older than this is triaged from git, not /tmp.
LOGDIR_KEEP_MAX = 40
# Scratch from the ENDLESS idle paths (bench rounds, fuzz rounds). They carry no
# pid, so age is the only liveness proxy — generous enough that a long bench
# round in flight is never reaped out from under itself.
IDLE_KEEP_SECS = 2 * 3600

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
        self.attempts = 0         # launch count; retriable classes may re-run
        self.flaky = False        # failed at least once, then passed on retry
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
            # point every invocation at the run's snapshot (see RUN_COMPILER)
            if os.path.exists(RUN_COMPILER):
                body = COMPILER_PATH_RE.sub(RUN_COMPILER, body)
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
            or "sqlite" in text or "zlib" in text or "/lua/" in text
            # uforth is a corpus like the others, it just lives outside
            # library_candidates (it is its own repo at $(UFORTH_SRC)), so the
            # path heuristic missed it and it fell through to `unit` — a 90s
            # timeout. That was survivable at 46s; enrolling Gerry Jackson's 13
            # ANS word sets took the job past TEN MINUTES, so testmgr killed it
            # and published a RED that was purely the harness misjudging the
            # class. Same false-red family as the rest of today: a job that did
            # not finish is not a job that failed.
            or "uforth" in text):
        return "corpus"
    if "run_target.sh" in text or "qemu" in text:
        return "qemu"
    return "unit"


# ------------------------------------------------------------ generation ---
def make_dry_run(target, overrides=None):
    """The recipe lines `make` would run for `target`.

    `overrides` are VAR=value pairs appended to the command line, which is how
    a target gets sharded without a second copy of its recipe: the uforth shards
    pass a one-element UFORTH_WORDSETS and an empty UFORTH_CORPUS, and make
    expands the same recipe around the narrower list.
    """
    cmd = ["make", "-n", "--no-print-directory", target]
    cmd += ["%s=%s" % kv for kv in (overrides or {}).items()]
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
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


def uforth_shards():
    """[(shard-label, {make overrides}), ...] — one per ANS word set, plus one
    for the uforth-native corpora.

    Why this target and not another: `test-uforth` was a SINGLE serial job of
    ~790s (learned EWMA), and it is enrolled in both `limited` and `full`. Those
    tiers carry 1064s and 1967s of total work, so on a 12-core box their
    parallel floor is 89s and 164s — meaning BOTH tiers' wall time was set by
    this one job, with eleven cores idle behind it. Sharding is the whole
    difference between a 13-minute tier and a ~4-minute one.

    The list comes from `make print-UFORTH_WORDSETS`, never a copy of it here:
    a word set added to the Makefile must not silently keep running inside
    somebody else's shard (that is exactly the invisible-coverage hole
    test-nilpy and test-uforth were both found in). If make cannot be asked,
    fall back to ONE unsharded job rather than guessing a list — a slow tier is
    a cost, a wrong list is a coverage lie.
    """
    try:
        # NOT `make -n`: under -n make would PRINT the `@echo` line instead of
        # running it, and the recipe text would parse as the word list
        # (`echo`, `'core.fr`, ...). print-% must actually execute.
        sets = subprocess.run(
            ["make", "--no-print-directory", "print-UFORTH_WORDSETS"],
            cwd=REPO, capture_output=True, text=True, timeout=60)
        names = sets.stdout.split() if sets.returncode == 0 else []
    except (OSError, subprocess.SubprocessError):
        names = []
    if not names:
        return []
    out = [("corpus", {"UFORTH_WORDSETS": ""})]
    for n in names:
        # strip the extension for the label: `blocktest.fth` -> `blocktest`,
        # so the job name reads test-uforth#blocktest.
        out.append((n.rsplit(".", 1)[0],
                    {"UFORTH_CORPUS": "", "UFORTH_WORDSETS": n}))
    return out


def generate(tier):
    jobs = []
    for tgt in TIERS[tier]:
        if tgt == "test-uforth":
            shards = uforth_shards()
            for label, ov in shards:
                for job in split_jobs(tgt, make_dry_run(tgt, ov)):
                    job.name = "%s#%s" % (tgt, label)
                    jobs.append(job)
            if shards:
                continue
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
    if tier in SELFHOST_GATE_TIERS:
        jobs.append(selfhost_fixedpoint_job())
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


def selfhost_fixedpoint_job():
    """The self-host gate, as a JOB.

    It used to be asserted only inside `make compiler/pascal26`, which meant a
    broken gate looked like a broken box: make failed, testmgr exited rc=1, and
    the watcher logged "no report — infra problem, not recording a verdict".
    The single most important property in the project failed SILENTLY, 1445
    times in the borg log. As a job it can be RED, bisected to a culprit, and
    ticketed like anything else.

    Seeds from the committed pinned stable, so the answer is identical on every
    box; see tools/selfhost_fixedpoint.sh for the two properties it checks.
    """
    j = Job("selfhost-fixedpoint", 0, ["tools/selfhost_fixedpoint.sh"])
    j.name = "selfhost-fixedpoint#00"
    j.cls = "selfhost"
    j.sel = "selfhost-fixedpoint#src:compiler/compiler.pas"
    j.est_mem = CLASSES["selfhost"]["est_mem"]
    return j


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
        # co-tenancy state: when we last SAW another clone's run, and which
        # repos they came from (reported at the end, so a red read months later
        # still says the box was shared)
        self._peer_polled = -PEER_POLL_PERIOD
        self.peer_last_seen = -1.0
        self.peer_repos = set()
        self.metrics = load_metrics()
        for j in jobs:
            cls_to = CLASSES[j.cls]["timeout"]
            m = self.metrics.get(metrics_key(j))
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
        # The self-host fixedpoint launches FIRST, ahead of the longest-job
        # heuristic. It is the one red that invalidates every other track's
        # ground, and since dev tracks stopped running suites locally, T's
        # report latency IS the dev loop's latency — a late self-host red now
        # costs commits to unwind, not minutes.
        # The FPC seed canary joins the front group for the same reason, minus
        # the abort. It broke four times in three days (2026-08-01..03), always
        # a one-line missing forward, and always found hours later once the
        # author's context was gone — because pxx's frontend resolves a call to
        # a function defined later in the same include and FPC, being
        # single-pass, does not. So the property is invisible to every check a
        # dev runs, and the whole ask of
        # feature-t-fpc-seed-canary-closer-to-the-dev-loop is latency.
        #
        # It is 10.7s and appended LAST by generate(), so among ~1200 jobs its
        # verdict landed late in the run for no reason. First means it is known
        # at ~11s. It stays ADVISORY — it must never abort the run the way a
        # self-host red does; making it a gate is explicitly out of scope.
        front = (SELFHOST_GATE_TARGET, FPC_CANARY_TARGET)
        self.queue = sorted(jobs, key=lambda j: (
            0 if j.target in front else 1,
            -(j.exp_dur if j.exp_dur else CLASSES[j.cls]["timeout"])))
        # cores/mem-aware admission does the real throttling; the cap is just
        # a runaway guard, and >nproc lets io/qemu-idle jobs keep cores busy
        self.hard_cap = 1 if args.serial else (args.jobs or self.nproc * 2)
        self.selfhost_red = False
        self.prev_cpu = cpu_times()
        self.idle_frac = 1.0
        self.interrupted = False
        self.deadline = time.monotonic() + args.deadline
        self._started = time.time()
        # Forward-progress guarantee. See admit_forced() -- the admission gates
        # look at GLOBAL machine state (PSI, swap, MemAvailable), so a loaded box
        # can hold every job back forever. That is only sound while something of
        # OURS is running and will finish and free the resource. With nothing
        # running, waiting cannot help: it is a deadlock, not backpressure.
        self._last_progress = time.monotonic()
        self._degraded = False

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
        job.attempts += 1
        self.running.append(job)

    def kill_group(self, job, sig=signal.SIGKILL):
        try:
            os.killpg(job.proc.pid, sig)
        except (ProcessLookupError, PermissionError):
            pass

    def poll_peers(self, now):
        """Notice another clone's testmgr, cheaply and repeatedly.

        Repeatedly because the contention that produced the false red started
        MID-RUN: the watcher was already going when a dev session launched its
        own gate. A startup-only check would have seen an idle box and drawn
        exactly the wrong conclusion.
        """
        if now - self._peer_polled < PEER_POLL_PERIOD:
            return
        self._peer_polled = now
        peers = foreign_runs()
        if not peers:
            return
        self.peer_last_seen = now
        for pid, repo, tier, _age in peers:
            if repo not in self.peer_repos:
                self.peer_repos.add(repo)
                print("testmgr: NOTE another testmgr shares this box — pid %d, "
                      "%s, tier %s. Both size their parallelism to the whole "
                      "box, so long jobs get %.0fx timeouts here and a kill is "
                      "retried, not called RED."
                      % (pid, repo, tier, PEER_TIME_FACTOR), flush=True)

    def contended(self, job):
        """Was another clone's run live at any point while THIS job ran?

        Deliberately "since the job started" rather than "right now": the peer
        may have finished in the second between killing us and our reap.
        """
        return job.t0 is not None and self.peer_last_seen >= job.t0

    def effective_timeout(self, job):
        # Stretch rather than retry where we can: a 111s job re-run three times
        # under contention costs more than giving it the room it needs once.
        return job.timeout * (PEER_TIME_FACTOR if self.contended(job) else 1.0)

    def _retriable_contention(self, job, why):
        """A kill/timeout while a co-tenant run was live is a statement about
        the BOX, not the artifact. Any class may retry it — the single-shot
        rule protects against nondeterminism in the code under test, and being
        killed by another tenant's load is not that."""
        if job.advisory or job.attempts >= RUN_RETRY_TRIES:
            return False
        if not self.contended(job):
            return False
        self._requeue_retry(job, "%s while another testmgr shared the box" % why)
        return True

    def _retriable(self, job):
        # Re-run a FAILED job before calling it RED, only in the
        # runtime-nondeterministic classes and only while attempts remain.
        # Advisory jobs never gate, so retrying them just burns time.
        return (not job.advisory
                and job.cls in RUN_RETRY_CLASSES
                and job.attempts < RUN_RETRY_TRIES)

    def _retriable_signature(self, job):
        """A HARNESS-level failure that any class may retry — see
        RUN_RETRY_SIGNATURES. Returns the matched signature, or None.

        Deliberately independent of job.cls: the point is that `Text file busy`
        is an exec race in the harness, not a statement about the artifact, so
        the single-shot rule it bypasses is not the rule it would undermine.
        Advisory jobs are still skipped — they gate nothing, so a retry only
        costs time."""
        if job.advisory or job.attempts >= RUN_RETRY_TRIES or not job.logpath:
            return None
        try:
            with open(job.logpath, "rb") as f:
                try:
                    f.seek(-RUN_RETRY_SIG_TAIL, os.SEEK_END)
                except OSError:            # log shorter than the tail window
                    f.seek(0)
                tail = f.read().decode(errors="replace")
        except OSError:
            return None
        return next((s for s in RUN_RETRY_SIGNATURES if s in tail), None)

    def _requeue_retry(self, job, why):
        # A transient failure: put the job back on the queue for another launch
        # instead of finalizing it RED.  Do NOT add to `done` — it re-enters the
        # normal admission path and launch() bumps job.attempts.
        print("testmgr: %s %s on attempt %d/%d — retrying (flake guard)"
              % (job.name, why, job.attempts, RUN_RETRY_TRIES), flush=True)
        self.running.remove(job)
        job.proc = None
        job.t0 = job.t1 = None
        job.status = "queued"
        self.queue.append(job)

    # A target that guards its own precondition exits 0 when the precondition
    # is absent, so it lands as a PASS — indistinguishable from having run.
    # `test-uforth` on a box without ~/projects/uforth is the case that forced
    # this: enrolling it in a tier would otherwise have bought a green that
    # tested nothing, which is the exact failure
    # feature-t-enroll-uforth-in-the-tiers warns about ("a SKIP that nobody
    # notices is the failure mode to avoid here").
    #
    # Deliberately anchored: the marker must be `<target>: SKIP` at the start
    # of a line. The looser match is what bug-t-corpus-regex-invents-phantom-
    # tree was about — a regex that matched the PROSE of a skip message and
    # skipped things forever. A bundled job whose *individual recipe line*
    # self-skips is unaffected, because that line does not print this shape
    # with the job's own target name.
    _SKIP_RE_CACHE = {}

    def _self_skipped(self, job):
        if not job.logpath or not os.path.exists(job.logpath):
            return False
        pat = self._SKIP_RE_CACHE.get(job.target)
        if pat is None:
            pat = re.compile(rb"(?m)^%s: (?:corpus )?SKIP\b"
                             % re.escape(job.target.encode()))
            self._SKIP_RE_CACHE[job.target] = pat
        try:
            with open(job.logpath, "rb") as f:
                return bool(pat.search(f.read()))
        except OSError:
            return False

    def reap(self):
        done = []
        now = time.monotonic()
        for job in list(self.running):
            rc = job.proc.poll()
            if rc is not None:
                if rc == 0:
                    job.t1 = now
                    # "skip", NOT "skipped": the two are different outcomes and
                    # the run loop treats "skipped" as a dependency failure, so
                    # using it here turned a box that merely lacks the uforth
                    # checkout RED — the exact false red the enrolment ticket
                    # forbids. "skip" is the pass-equivalent did-not-run status
                    # (corpus-absent uses it), which is what this is.
                    job.status = "skip" if self._self_skipped(job) else "pass"
                    if job.attempts > 1:
                        job.flaky = True   # failed earlier, recovered on retry
                    self.running.remove(job)
                    done.append(job)
                    self.learn(job)
                elif self._retriable(job):
                    self._requeue_retry(job, "failed (rc=%d)" % rc)
                elif self._retriable_signature(job):
                    # single-shot classes included: the signature, not the
                    # class, is what makes this safe to re-run
                    self._requeue_retry(
                        job, "failed (rc=%d) with a harness signature (%s)"
                             % (rc, self._retriable_signature(job)))
                elif (rc < 0 and -rc in CONTENTION_SIGNALS
                      and self._retriable_contention(
                          job, "killed by SIG%s"
                               % signal.Signals(-rc).name.removeprefix("SIG"))):
                    # A job the OS killed never produced a verdict. This is the
                    # exact shape of the false NEW-RED: `Terminated` in the log
                    # with the compile line reading `ok:`.
                    pass
                else:
                    job.t1 = now
                    job.status = "fail"
                    self.running.remove(job)
                    done.append(job)
            elif now - job.t0 > self.effective_timeout(job):
                self.kill_group(job)
                job.proc.wait()
                if self._retriable(job):
                    self._requeue_retry(job, "timed out")
                elif self._retriable_contention(job, "timed out"):
                    pass
                else:
                    job.t1 = now
                    job.status = "timeout"
                    # A job that timed out ran AT LEAST this long. Record that
                    # as a lower bound, because otherwise a job that gets much
                    # slower can never learn its new duration: the hang
                    # detector caps the budget at exp_dur*10+15, learn() only
                    # runs on PASS, and so the stale-fast expectation kills
                    # every future run forever.
                    #
                    # Measured 2026-08-08: test-uforth learned 17.8s over 5
                    # runs, then Track N enrolled 13 ANS word sets and it
                    # became a 1416s job. Budget stayed min(1200, max(45, 192,
                    # 300)) = 300s, so it timed out, so it never learned, so it
                    # timed out — a permanent false RED with no way out but a
                    # human deleting the metric.
                    #
                    # Safe against a genuinely hung job: the class ceiling
                    # still bounds the next budget (min(cls_to * scale, ...)),
                    # so the worst case is one class-length run, not unbounded
                    # growth.
                    self.learn_timeout(job)
                    self.running.remove(job)
                    done.append(job)
        return done

    def learn_timeout(self, job):
        """Raise the stored expectation to what we OBSERVED before killing it.

        Not a pass, so nothing else about the metric is trusted — only that the
        job demonstrably needed more time than we gave it.
        """
        observed = max(0.05, (job.t1 - job.t0) / self.scale)
        key = metrics_key(job)
        m = dict(self.metrics.get(key) or {})
        if m.get("dur", 0) >= observed:
            return
        m["dur"] = observed
        m.setdefault("cpu", 1.0)
        m.setdefault("mem", CLASSES[job.cls]["est_mem"])
        m["n"] = int(m.get("n") or 0)      # not a passing sample; do not count
        self.metrics[key] = m
        print("testmgr: %s timed out at %.0fs — raising its expected duration "
              "from the stale value so the next run gets room (was killed by "
              "the hang detector, not by the class ceiling)"
              % (job.name, observed), flush=True)

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
        key = metrics_key(job)
        m = self.metrics.get(key)
        if not m:
            self.metrics[key] = {"dur": round(dur, 2), "mem": mem,
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
        # The swap floor must scale with the box, or it becomes a permanent
        # lockout. A flat 1000 MB is a QUARTER of a 4 GB swap and a rounding
        # error on a 32 GB one. Observed on borg: 8 GB MemAvailable, memory PSI
        # flat 0.00 (i.e. not thrashing at all), yet every job was held back
        # because free swap was 965 MB against the 1000 MB floor -- a 35 MB miss.
        # And it never recovers: the used swap is stale anon pages from
        # long-lived desktop processes that will never be handed back. So the
        # gate stayed shut forever and every run crawled in degraded serial mode.
        # min() keeps this NO LESS conservative than before on big-swap boxes.
        floor = min(SWAP_FLOOR, int(mi.get("SwapTotal", 0) * SWAP_FLOOR_FRAC))
        psi = mem_pressure()
        # Scaling the floor was not enough: free swap is not a pressure signal
        # at all on a desktop box, where swap fills with stale anon pages from
        # long-lived processes (browser tabs) that are never handed back. The
        # floor then latches shut permanently and admit_forced drips the run
        # through one job at a time in degraded serial mode -- 1011 jobs
        # serially, which reads as "the watcher isn't running anything".
        # Observed on borg 2026-07-20: 233 MB free swap under a 409 MB floor
        # while MemAvailable was 8.6 GB and memory PSI was flat 0.00 across
        # avg10/60/300. Low free swap only matters if the box is ACTUALLY
        # struggling, and PSI and MemAvailable measure that directly -- so
        # require one of them to corroborate before holding admission.
        # The PSI_ADMIT / MEM_FLOOR / PSI_KILL guards below are unchanged, so
        # a box that genuinely starts thrashing is still caught.
        swap_low = (mi.get("SwapTotal", 0)
                    and mi.get("SwapFree", 0) < floor)
        if swap_low and (psi > PSI_QUIET
                         or mi.get("MemAvailable", 0) < SWAP_GATE_AVAIL):
            self.note_stall("swap critically low (%d MB free, floor %d MB) "
                            "with PSI %.1f%% / MemAvailable %d MB"
                            % (mi["SwapFree"] >> 20, floor >> 20, psi,
                               mi.get("MemAvailable", 0) >> 20))
            return False
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

    def admit_forced(self, now):
        """THE self-heal: never sit idle with work queued.

        The admission gates in admit_ok() are all GLOBAL machine state -- memory
        PSI, swap floor, MemAvailable. None of them is about us. So a box loaded
        by somebody else (another agent's run, the twatch daemon, a browser)
        holds back every job we have, and we sleep in the scheduler loop making
        no progress until the global deadline fires, tens of minutes later. That
        is what a "hung" testmgr actually is: not stuck, STARVED.

        Backpressure is only sound while something of ours is RUNNING -- that job
        will finish and release memory, so waiting is productive. With
        self.running empty there is nothing to wait for and no reason to think
        the next tick differs from this one. Deadlock, not backpressure.

        So: nothing running + work queued + no progress for STARVE_GRACE seconds
        => force ONE job through the gates, loudly. One at a time, so we degrade
        to serial execution on a hostile box rather than piling on. Progress is
        slow instead of absent, and the run always terminates.
        """
        if self.running or not self.queue:
            self._degraded = False      # normal admission works again
            return None
        # Once starvation is established, DON'T re-serve the full grace period
        # before every subsequent job: the box is hostile, we already know, and
        # re-proving it costs STARVE_GRACE seconds per job (90s x 11 jobs = 16
        # minutes of sitting still, which is most of the "hang" all over again).
        # Stay in degraded mode -- force jobs back-to-back, one at a time -- until
        # a job passes the real gates on its own.
        grace = TICK if self._degraded else STARVE_GRACE
        if now - self._last_progress < grace:
            return None
        announced = self._degraded      # read BEFORE we set it, or the banner never prints
        self._degraded = True
        # Cheapest job first: the likeliest to fit, and the one that gets the
        # progress clock ticking again with the least added pressure.
        job = min(self.queue, key=lambda j: j.est_mem)
        if not announced:
            # WHY the gates are shut is a MEASUREMENT, not an assumption. This
            # line used to assert "OTHER load on this box" unconditionally --
            # false whenever the cheapest queued job simply does not fit here,
            # which is the common case (one 6.8 GB job on a 16 GB box). That
            # wrong assertion cost a 2026-07-20 investigation most of a day:
            # it says "not our fault", so the job's own footprint never gets
            # suspected. Name the binding constraint instead of guessing it.
            mi = meminfo()
            avail = mi.get("MemAvailable", 0)
            if avail - job.est_mem <= MEM_FLOOR:
                why = ("the cheapest queued job (%s) is estimated at %d MB and "
                       "only %d MB is available (floor %d MB) — it does not fit "
                       "alongside anything on this box"
                       % (job.name, job.est_mem >> 20, avail >> 20,
                          MEM_FLOOR >> 20))
            else:
                why = ("the memory gates are held by OTHER load on this box "
                       "(%d MB available, PSI %.1f%%, %d MB free swap)"
                       % (avail >> 20, mem_pressure(),
                          mi.get("SwapFree", 0) >> 20))
            print("testmgr: STARVED %.0fs — %d jobs queued, none running, and %s. "
                  "Forcing jobs through one at a time (degraded/serial) rather "
                  "than stalling to the deadline."
                  % (now - self._last_progress, len(self.queue), why), flush=True)
        print("testmgr: forcing %s (degraded)" % job.name, flush=True)
        return job

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
                self._last_progress = time.monotonic()   # a finished job IS progress
                dur = job.t1 - job.t0
                # SKIP is its own mark, never "ok": a target that guarded its
                # own precondition and exited 0 tested nothing, and the whole
                # point of detecting it is that it must not read as a pass.
                mark = {"pass": "ok", "fail": "FAIL", "timeout": "TIMEOUT",
                        "skip": "SKIP"}.get(job.status, job.status.upper())
                if job.advisory and job.status != "pass":
                    mark = "NOTICE"
                elif job.flaky:
                    mark = "flaky"          # passed, but only after a retry
                print("  [%4d/%d] %-7s %-28s %6.1fs%s" %
                      (self.done_count(), len(self.jobs), mark, job.name, dur,
                       "  (flaked, recovered on attempt %d)" % job.attempts
                       if job.flaky else ""),
                      flush=True)
                # "skip" is pass-equivalent for the GATE: the target guarded
                # its own precondition and exited 0, so there is no evidence of
                # breakage — only of absence. Counting it as a failure is how
                # enrolling test-uforth would have turned every box lacking
                # ~/projects/uforth red, which the enrolment ticket explicitly
                # forbids. It stays visible as SKIP in the report and the
                # job list; visibility is the goal, not a red.
                if job.status not in ("pass", "skip") and not job.advisory:
                    failed = True
                    # A broken self-host fixedpoint makes every other verdict at
                    # this sha suspect — the binary under test cannot reproduce
                    # itself. Tear down and let the caller publish NOW rather
                    # than after the remaining tier. Aborting is what makes the
                    # existing end-of-run publish immediate; no second publish
                    # path, so twatch's hard-won rebase/conflict handling is not
                    # exercised more often than it already is.
                    if job.target == SELFHOST_GATE_TARGET:
                        self.selfhost_red = True
                        print("testmgr: SELF-HOST RED (%s) — tearing down the "
                              "rest of the tier; every other verdict at this "
                              "sha is suspect" % job.name, flush=True)
                        self.teardown()
                        for j in self.queue:
                            j.status = "skipped"
                        self.queue = []
                        return 1
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
            self.poll_peers(now)
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
                self._last_progress = now
            # Nothing admitted and nothing running? Then waiting is pointless --
            # force one job through rather than stalling to the deadline.
            if not launched:
                forced = self.admit_forced(now)
                if forced is not None:
                    self.queue.remove(forced)
                    self.launch(forced)
                    self._last_progress = now
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


PINNED_REL = "stable_linux_amd64/default/pinned"


def unseed_pinned():
    """Never let the matrix run against a binary that IS the pinned seed.

    The documented fresh-box step is `make seed-from-stable`, which COPIES
    `pinned` onto `compiler/pascal26`. The copy gets a fresh mtime, newer than
    `compiler/compiler.pas`, so the `make compiler/pascal26` below is told
    "up to date" and no self-host build ever happens: the whole sweep tests the
    PINNED binary rather than a compiler built from the checked-out sources.
    Measured on xeon at 110774a14648 — byte-identical to `pinned`, mtime 13
    minutes newer than the sources, 17 jobs red.

    The window is not just the first run. It persists for every sha whose diff
    does not touch a compiler source — a tstate commit, a docs commit, a
    `lib/**` commit — because nothing bumps a source mtime past the binary. That
    is a concrete mechanism for the phantom-NEW-RED family: jobs go red against
    a stale compiler, then "fix themselves" at the next sha that happens to
    touch `compiler/**`, with no commit in the range able to explain either
    transition. Only selfhost-fixedpoint can see it, and when it does it reads
    as a scary self-host regression rather than "your seed is stale".

    twatch backdates the seed after a fresh clone, but only under
    `if not os.path.exists(comp)` — so every clone after its first cycle, and
    every manual run, is exposed. The invariant belongs where the matrix runs.
    Deliberately NOT fixed by editing the `seed-from-stable` rule: the Makefile
    is Track A's ground. task-t-seed-from-stable-defeats-rebuild.
    """
    comp = os.path.join(REPO, COMPILER)
    pinned = os.path.join(REPO, PINNED_REL)
    if not (os.path.exists(comp) and os.path.exists(pinned)):
        return False
    if file_sha256(comp) != file_sha256(pinned):
        return False
    # Backdate the binary rather than touching a source: touching
    # compiler.pas would make it newer than everything else and can cascade
    # into other mtime-driven rules; an epoch-old binary simply loses to every
    # source, which is exactly the ordering make should have seen.
    os.utime(comp, (0, 0))
    print("testmgr: %s is byte-identical to %s — that is the seed, not a "
          "build. Backdated it so `make` rebuilds from source; otherwise this "
          "run would have tested the PINNED binary." % (COMPILER, PINNED_REL),
          flush=True)
    return True


def build_compiler():
    """Build the compiler into paths PRIVATE to this clone.

    The Makefile's BUILD_COMPILER/VERIFY_COMPILER default to the fixed global
    paths /tmp/pascal26-build and /tmp/pascal26-verify -- shared by every clone
    on the box. Two testmgr runs in DIFFERENT checkouts (a dev gate in one, the
    twatch daemon's in another) therefore write the same two files, and the
    self-host fixedpoint step then `cmp`s one clone's binary against the
    OTHER's. It reports "differ: byte 97" and the run dies with a self-host
    failure that never happened -- a fabricated regression on the very gate that
    blesses the stable binary. Reproduced here on 2026-07-13 while testing the
    run lock; it is the non-job half of chore-makefile-testtmp-parameterize
    (testmgr already rewrites /tmp/ for JOB scripts, but `make` runs outside
    that rewrite).

    The run lock cannot fix this: the collision is between REPOS, not within one.
    These are plain `:=` make variables, so overriding them on the command line
    needs no Makefile change (that sweep stays Track A's ticket).
    """
    unseed_pinned()
    priv = "/tmp/pascal26-build-%s" % REPO_TAG
    r = subprocess.run(["make", "--no-print-directory", COMPILER,
                        "BUILD_COMPILER=%s-build" % priv,
                        "VERIFY_COMPILER=%s-verify" % priv,
                        "BUILD_COMPILER_MANAGED=%s-mbuild" % priv,
                        "VERIFY_COMPILER_MANAGED=%s-mverify" % priv], cwd=REPO)
    if r.returncode == 0:
        return True
    # The make rule demands a ONE-PASS fixedpoint: seed compiles the sources to
    # stage2, stage2 compiles them to stage3, cmp stage2 stage3. That holds only
    # if the seed ALREADY matches the current sources. It does not after any
    # codegen-changing commit -- stage2 was produced by the old seed, stage3 by
    # the new stage2, so they legitimately differ and convergence needs one more
    # round. Bootstraps have always worked this way.
    #
    # A watcher hops across SHAs with a persistent compiler/pascal26, so its seed
    # is stale constantly: `differ: byte 97` appeared 1445 times in the borg log,
    # each one killing testmgr before it ran a single test ("no report (rc=1) --
    # infra problem, not recording a verdict"). That is why the watcher kept
    # falling behind: it was not testing, it was failing to build.
    #
    # So iterate to a REAL fixedpoint -- but bounded, and still fail loudly if it
    # never converges: a compiler that cannot reproduce itself is a genuine bug,
    # and quietly looping until it does would hide exactly the thing the
    # self-host gate exists to catch.
    if not converge_seed(priv):
        print("testmgr: building %s failed" % COMPILER, flush=True)
        return False
    return True


def report_build_failure(args):
    """Report an unbuildable compiler as INFRA — a run that did not happen.

    This used to emit a RED verdict carrying a synthetic failing
    `selfhost-fixedpoint#00` job, so that a build failure would "act like a
    normal red": bisected to a commit and filed as a regression. That was
    backwards, and on 2026-08-07 it cost plexus a day of false reds. A build
    failure is a statement about THIS BOX (a stale or poisoned seed binary,
    a missing toolchain, a full disk), not about the sources — and the box is
    exactly the thing a per-sha verdict is not allowed to be about. The
    synthetic job then made it worse: it diffed to NEW-RED, opened a ledger
    entry, and the bisector narrowed it to an innocent commit
    (4ce9b3fc0974), which a lane could legitimately have reverted.

    So: emit a report — the watcher NEEDS to see this, and dying rc=1 with no
    report is what made the failure look like a mystery — but emit it as
    `INFRA` with NO jobs. No jobs means nothing can be diffed, so no NEW-RED,
    no ledger entry, and no bisect can be manufactured out of it. twatch
    treats INFRA as "reseed from the pinned stable and retry once", and
    reports the host DEGRADED if that does not fix it. The sha stays untested
    and honestly says so, which is the whole point: a broken box must not be
    able to say "master is broken".
    """
    print("\n== testmgr report (tier %s) ==\n  INFRA    the compiler cannot be "
          "built from these sources on this box — no verdict\n" % args.tier)
    if args.report_json:
        rep = {"tier": args.tier, "wall": 0.0, "scale": 1.0,
               "verdict": "INFRA",
               "reason": "compiler build failed (see log); no test was run",
               "slow": [], "jobs": []}
        with open(args.report_json, "w") as f:
            json.dump(rep, f, indent=1)
    return 1


def converge_seed(priv, max_rounds=4):
    """Iterate seed -> stage_n until stage_n reproduces itself, then install it.

    Returns True if a fixedpoint was reached (and compiler/pascal26 now holds it).
    """
    src = os.path.join(REPO, "compiler", "compiler.pas")
    seed = os.path.join(REPO, COMPILER)
    if not os.path.exists(seed):
        return False
    print("testmgr: seed is stale for these sources (one-pass fixedpoint failed) "
          "— iterating the bootstrap to convergence", flush=True)
    cur = seed
    for rnd in range(1, max_rounds + 1):
        a = "%s-iter%d-a" % (priv, rnd)
        b = "%s-iter%d-b" % (priv, rnd)
        for stage, out in ((cur, a), (a, b)):
            r = subprocess.run([stage, src, out], cwd=REPO,
                               stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
            if r.returncode != 0 or not os.path.exists(out):
                print("testmgr: bootstrap round %d failed to compile" % rnd,
                      flush=True)
                return False
        if filecmp.cmp(a, b, shallow=False):
            # a reproduces itself byte-for-byte: that IS the fixedpoint.
            shutil.copyfile(a, seed)
            os.chmod(seed, 0o755)
            print("testmgr: bootstrap converged after %d round(s) — seed refreshed"
                  % rnd, flush=True)
            return True
        cur = a         # not yet: use this stage as the next seed
    print("testmgr: bootstrap did NOT converge in %d rounds — this is a real "
          "self-host bug, not a stale seed" % max_rounds, flush=True)
    return False


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
BENCH_RUNS = 5                 # target CLEAN runs; the number is min over them
BENCH_SELF_RUNS = 3            # self-compile is ~10s a run: 3 is plenty
BENCH_EXTRA_TRIES = 5          # spare attempts to replace runs lost to contention
BENCH_SLOW_PCT = 10.0
# Contention guard. A single-threaded CPU benchmark spends ~all its wall time ON
# a cpu, so child cpu-time (user+sys, from rusage) ~= wall. When wall runs ahead
# of cpu the process was descheduled -- another load spiked during the run -- and
# that timing is contaminated: discard it and take another run (this is the
# before/during/after cpu check, done per run from the child's own accounting
# rather than by sampling the box). Kept runs' MIN is the reported number, so a
# spike can only ever be thrown away, never averaged in. Tunable for noisy hosts.
BENCH_CPU_WALL_MAX = float(os.environ.get("TESTMGR_BENCH_CPU_WALL_MAX", "1.06"))
BENCH_CPU_MIN_S = 0.03        # below this, wall/cpu is startup jitter -- don't judge
BENCH_QUIET_LOAD_FRAC = 0.60  # per-core load1 above this: box busy, wait to start
BENCH_QUIET_WAIT_S = 10.0     # cap on that pre-run wait (no-op on a quiet host)
BENCH_TSV_REL = "devdocs/progress/tstate/bench.tsv"
# The clock a row was taken at, as a FACT rather than an inference
# (bug-t-bench-slowdowns-are-quantized-by-cpu-p-state: on the E5-2620 v2 the
# 2.6/2.1 GHz boost-to-base ratio is 1.238, and the slow rows land at a median
# 1.242 — the inflation is a P-state step, not a contention continuum).
#
# A SIDE FILE, not more columns in bench.tsv, for the same reason
# record_host_epoch() gave: bench.tsv is indexed POSITIONALLY and columns 6/7
# are already uforth_sha/rss_kb on the cross-runtime rows, so a new column at 6
# would silently reinterpret every uforth row. Joined on (date, host, workload,
# level) — `date` is one timestamp per batch, so the join is exact.
BENCH_CLOCK_TSV_REL = "devdocs/progress/tstate/bench-clock.tsv"
COMPILER_SRC = "compiler/compiler.pas"
# FPC comparison (feature-testmgr-fpc-compare-and-web-dashboard): the `fpc`
# level in bench.tsv times the reference compiler on the same source so the
# dashboard can show pxx-vs-FPC. Flags mirror the Makefile bootstrap.
FPC_BIN = os.environ.get("FPC", "fpc")
# -Mobjfpc is load-bearing, not decoration: in FPC's DEFAULT mode `integer` is a
# 16-bit smallint, so a source with a literal like 1000000 is rejected outright
# ("range check error while evaluating constants") -- which silently dropped sieve
# from the comparison. pxx implements the objfpc dialect, so anything else compares
# against a language we do not claim to be.
FPC_FLAGS = ["-Mobjfpc", "-O2", "-Tlinux", "-Px86_64"]
FPC_LEVEL = "fpc"
# (name, source, canary argv, timed argv, fpc_ok) — canary mode must be
# deterministic; {tmp} expands to the bench scratch dir. fpc_ok marks sources
# in the common pascal26/FPC subset (no pxx-only units) that are ALSO compiled
# and timed under `fpc -O2` for the cross-compiler `fpc` level.
BENCH_SUITE = (
    ("mandelbrot", "examples/mandelbrot/mandelbrot.pas",
     [], ["--bench", "1600", "1200"], False),       # float compute (pxx units)
    # The same float kernel with NO units, so FPC can compile it too and the `fpc`
    # level gets a float-compute row. The example above stays as it is -- it is a
    # demo and exists to USE our libraries; a benchmark should not depend on any,
    # or a library change moves the number and nobody knows what did it.
    ("mandelbrot-p", "bench/portable/mandelbrot.pas",
     ["200", "150"], ["1600", "1200"], True),       # float compute, FPC-comparable
    ("raytracer", "examples/raytracer/raytracer.pas",
     [], ["--ppm", "{tmp}/rt.ppm", "480", "360"], False),  # call-heavy float
    # Same scene + Double kernel with only `math` (Sqrt), no image/png/hashing/
    # platform, so FPC compiles it and the `fpc` level gets a call-dense float
    # row. Canary = default 96x64 smoke (self-checks its checksum within a
    # tolerance band and Halt(1)s outside it); timed = 480x360. The demo above
    # stays as-is -- it exists to USE our image libraries; this is a fixture.
    ("raytracer-p", "bench/portable/raytracer.pas",
     [], ["480", "360"], True),                     # call-dense float, FPC-comparable
    ("sieve", "examples/primes/sieve.pas", [], [], True),   # memory-bound int, FPC-comparable
    ("nbody", "bench/portable/nbody.pas", [], [], True),   # float, FPC-comparable
    ("fib", "bench/portable/fib.pas", [], [], True),       # call-heavy int, FPC-comparable
)


def _wait_quiet():
    """Best-effort: if 1-min load per core is high, wait (up to
    BENCH_QUIET_WAIT_S) so timing does not start mid-spike. loadavg is coarse and
    averaged -- the real guard is the per-run cpu/wall check below; this just
    avoids obviously-bad starts. No-op where getloadavg is unavailable."""
    try:
        ncpu = os.cpu_count() or 1
        deadline = time.monotonic() + BENCH_QUIET_WAIT_S
        while time.monotonic() < deadline:
            if os.getloadavg()[0] / ncpu <= BENCH_QUIET_LOAD_FRAC:
                return
            time.sleep(1.0)
    except (OSError, AttributeError):
        pass


def _timed_run(argv, timeout):
    """Run argv once and return (wall_secs, cpu_secs, rc, peak_rss_kb).

    Uses os.wait4() — a BLOCKING reap — deliberately, and never
    `subprocess.run(..., timeout=)`.

    That kwarg was the entire "benchmark timings are quantized to a 50 ms grid"
    bug (bug-t-bench-sub-second-timings-quantized-to-50ms). Passing a timeout
    sends CPython down Popen._wait()'s POLLING path: it sleeps 0.5 ms, then
    doubles, capped at 50 ms, and checks waitpid(WNOHANG) after each nap. The
    wall time you measure is therefore not when the child exited, it is the
    next POLL WAKEUP after it exited. Cumulative wakeups land at

        0.5, 1.5, 3.5, 7.5, 15.5, 31.5, 63.5, 113.5, 163.5, 213.5, 263.5 ...

    which is exactly the grid bench.tsv shows (observed clusters 31.6-32.1,
    63.7-64.5, 113.7-114.4, 163.9-164.6, 213.x, 263.x ...). Measured proof: the
    same FPC-built sieve times 77.8-84.7 ms in a plain loop and a suspiciously
    stable 64.1-64.5 ms through the old bench_time — the harness was reporting
    the 63.5 ms wakeup, i.e. a number BELOW the true runtime, not merely a
    coarse one. 61% of all rows are sub-second, so most of the log was affected;
    on a 64 ms measurement a 50 ms grid is ±39%.

    wait4 also hands back per-child rusage for free, which replaces the old
    RUSAGE_CHILDREN differencing (that needed the driver to stay strictly
    serial to be meaningful) and yields peak RSS — the measurement
    feature-t-est-mem-from-measurement wants.

    The timeout is enforced by a watchdog thread instead, so a hung workload is
    still bounded; it just no longer taxes the measurement of every healthy run.
    """
    p = subprocess.Popen(argv, cwd=REPO, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    timed_out = []

    def _watchdog():
        timed_out.append(True)
        try:
            p.kill()
        except OSError:
            pass

    wd = threading.Timer(timeout, _watchdog)
    wd.start()
    t0 = time.monotonic()
    try:
        _, status, ru = os.wait4(p.pid, 0)
    finally:
        wd.cancel()
    wall = time.monotonic() - t0
    # We reaped the child behind Popen's back: tell it, or __del__ warns and
    # a later poll()/wait() would block on a pid that no longer exists.
    p.returncode = os.waitstatus_to_exitcode(status)
    if timed_out:
        return None, None, None, None
    return (wall, ru.ru_utime + ru.ru_stime, p.returncode, ru.ru_maxrss)


def cpu_mhz():
    """Mean MHz across online CPUs right now, or None where cpufreq is absent.

    None rather than a guess: a box without `cpufreq` (a VM, a container, some
    ARM boards) must record NO clock rather than a fabricated one, because the
    whole point of this column is that it is a measurement.
    """
    vals = []
    for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/"
                       "scaling_cur_freq"):
        try:
            with open(p) as f:
                vals.append(int(f.read().strip()) / 1000.0)   # kHz -> MHz
        except (OSError, ValueError):
            continue
    return sum(vals) / len(vals) if vals else None


def bench_time(argv, runs, timeout, label=""):
    """Min wall time over `runs` CLEAN runs, and the CPU clock it was taken at.

    A run is discarded (and replaced, up to runs+BENCH_EXTRA_TRIES attempts)
    when the child was descheduled -- wall > cpu*BENCH_CPU_WALL_MAX -- so a load
    spike is thrown away rather than recorded. If too few come back clean, the
    min over whatever did is returned and a `noisy` line is printed.

    Returns (secs, clock) -- secs None on failure/timeout. `clock` is
    (mhz, lo, hi): the clock during the run that PRODUCED the returned time,
    plus the range seen across all clean runs. Pairing the clock with the
    winning run specifically is the point: the reported number is a min, so the
    clock that explains it is the one that run saw, not a batch average.
    """
    _wait_quiet()
    max_tries = runs + BENCH_EXTRA_TRIES
    best_clean = best_any = None
    best_mhz = None
    seen = []
    clean = tries = 0
    while clean < runs and tries < max_tries:
        tries += 1
        before = cpu_mhz()
        wall, cpu, rc, _rss = _timed_run(argv, timeout)
        after = cpu_mhz()
        if wall is None or rc != 0:        # timeout, or the workload failed
            return None, None
        best_any = wall if best_any is None else min(best_any, wall)
        # descheduled? only judge once cpu is big enough that the ratio is signal
        if cpu is not None and cpu >= BENCH_CPU_MIN_S and \
           wall > cpu * BENCH_CPU_WALL_MAX:
            continue                       # contaminated -- discard, retry
        clean += 1
        mhz = None
        if before is not None and after is not None:
            mhz = (before + after) / 2.0
            seen.append(mhz)
        if best_clean is None or wall < best_clean:
            best_clean, best_mhz = wall, mhz
    if best_clean is None:                 # never got a clean run
        if label:
            print("  bench %-17s NOISY 0/%d clean in %d tries (box busy?)"
                  % (label, runs, tries))
        return best_any, None
    if clean < runs and label:
        print("  bench %-17s noisy: kept %d/%d clean in %d tries"
              % (label, clean, runs, tries))
    clock = (best_mhz, min(seen), max(seen)) if seen and best_mhz else None
    return best_clean, clock


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


STABLE_ROOT_REL = "stable_linux_amd64"
STABLE_DEFAULT_REL = STABLE_ROOT_REL + "/default"
PIN_STATE_REL = ".testmgr/pin-state.json"   # untracked scratch, like live.json


def _pin_paths():
    d = os.path.join(REPO, STABLE_DEFAULT_REL)
    return {"dir": d,
            "latest": os.path.join(d, "stable_latest"),
            "pinned_file": os.path.join(d, "stable_pinned"),
            "pinned_link": os.path.join(d, "pinned"),
            "builtin": os.path.join(d, "builtin"),
            "log": os.path.join(d, "pin.log"),
            "version": os.path.join(d, "VERSION")}


def _git(*a):
    return subprocess.run(["git"] + list(a), cwd=REPO, capture_output=True,
                          text=True)


def apply_pin_atomic(p, sha):
    """Flip the pin. Either it completed, or the tree is untouched.

    `make pin` is four separate mutations -- copy the binary, move the symlink,
    append pin.log, `rm -rf builtin` then repopulate it -- and a SIGINT between
    any two leaves a pin nobody can reason about. The `rm -rf` is the sharp one:
    interrupted there, the pinned compiler resolves `uses builtin` against a
    directory that is empty or half-written, and every consumer of $(PXX_STABLE)
    silently builds against the wrong RTL.

    So: stage everything OUTSIDE the live names (slow, fully interruptible --
    an abort here deletes a staging directory and nothing else), then block
    SIGINT/SIGTERM and do only renames. Every step in the critical section is
    rename(2) or an append, the whole of it is microseconds, and the signals
    that arrive during it are delivered after it, not into the middle of it.
    """
    stage = os.path.join(p["dir"], ".pin-staging.%d" % os.getpid())
    old_builtin = os.path.join(p["dir"], ".pin-old-builtin.%d" % os.getpid())
    shutil.rmtree(stage, ignore_errors=True)
    os.makedirs(stage)
    try:
        # --- interruptible: build the whole new pin off to the side ---
        shutil.copy2(p["latest"], os.path.join(stage, "stable_pinned"))
        sbuiltin = os.path.join(stage, "builtin")
        os.makedirs(sbuiltin)
        srcs = sorted(glob.glob(os.path.join(REPO, "compiler/builtin/*.pas")))
        if not srcs:
            raise RuntimeError("no compiler/builtin/*.pas to freeze")
        for s in srcs:
            shutil.copy2(s, sbuiltin)
        newsha = hashlib.sha256(
            open(os.path.join(stage, "stable_pinned"), "rb").read()).hexdigest()
        try:
            with open(p["pinned_link"], "rb") as f:
                oldsha = hashlib.sha256(f.read()).hexdigest()[:12]
        except OSError:
            oldsha = "none"
        try:
            with open(p["version"]) as f:
                ver = f.read().strip()
        except OSError:
            ver = "?"
        line = ("%s  pinned v%s  %s  (was %s)  %s\n"
                % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                   ver, newsha, oldsha, sha))
        # --- uninterruptible: renames only ---
        blocked = {signal.SIGINT, signal.SIGTERM}
        signal.pthread_sigmask(signal.SIG_BLOCK, blocked)
        try:
            os.replace(os.path.join(stage, "stable_pinned"), p["pinned_file"])
            tmplink = os.path.join(p["dir"], ".pinned.new.%d" % os.getpid())
            os.symlink("stable_pinned", tmplink)
            os.replace(tmplink, p["pinned_link"])   # atomic symlink swap
            have_old = os.path.isdir(p["builtin"])
            if have_old:
                os.rename(p["builtin"], old_builtin)
            os.rename(sbuiltin, p["builtin"])
            with open(p["log"], "a") as f:
                f.write(line)
        finally:
            signal.pthread_sigmask(signal.SIG_UNBLOCK, blocked)
        shutil.rmtree(old_builtin, ignore_errors=True)
        return newsha, len(srcs)
    finally:
        shutil.rmtree(stage, ignore_errors=True)


PIN_TIER_COST = {"quick": "~30s", "limited": "several minutes",
                 "full": "up to an hour — the whole cross-target matrix"}


def watcher_is_down():
    """Is Track T PROVEN down? `twatch --status` exit 1 is the documented test.

    Not "slow" and not "feels stale" — CLAUDE.md is explicit that those two
    commands are what answer it, so this asks rather than guesses. Any error
    reaching it counts as NOT down: a pin should not silently escalate to a
    long gate because a subprocess failed to launch.
    """
    try:
        return subprocess.run([sys.executable,
                               os.path.join(REPO, "tools/twatch.py"),
                               "--status"], cwd=REPO,
                              capture_output=True, timeout=60).returncode == 1
    except (OSError, subprocess.SubprocessError):
        return False


def pin_gate_tier(explicit, down):
    """Which tier gates a pin. Split out so both directions are testable.

    Defaults to QUICK, because `tools/gate.sh quick` is what CLAUDE.md names as
    THE pin gate. It used to default to `full`, which reintroduced through the
    gate exactly the cost the 2026-08-09 stabilize-fast decision removed through
    stabilize — 2305 jobs with the repo lock held, blocking every other lane —
    and two operators killed it as a hang because nothing said what it was doing
    (bug-t-testmgr-pin-gates-with-the-full-tier-by-default).

    The one escalation is the documented exception: when Track T is PROVEN down
    nothing else is sweeping the matrix, so breadth has to come from somewhere.
    `limited` rather than `full` — enough to be worth the wait, still not a
    release gate. Explicit --tier always wins, in both directions.
    """
    if explicit:
        return explicit
    return "limited" if down else "quick"


def run_pin(args):
    """Gate, stabilize, pin -- scheduled, resource-aware and INTERRUPTIBLE.

    feature-t-testmgr-owns-pinning-interruptible. `tools/gate.sh` is the pin
    gate, not the dev loop; the dev loop is `make compiler/pascal26` plus your
    repro. Pinning is the one step that must stay properly gated, because
    stable_linux_amd64/default/pinned is the ground Track B and every
    $(PXX_STABLE) consumer builds on: a red master is cheap and recoverable, a
    bad pin poisons another lane for hours.

    DELIBERATELY NOT A WATCHER CAPABILITY. The ticket asks this be decided
    explicitly rather than allowed to leak in: face 1 of Track T writes ONLY
    tstate/, and pinning writes the stable tree. So `--pin` is an operator
    command run on a dev box, and twatch never invokes it. Keeping the daemon's
    write scope to one directory is worth more than the convenience.
    """
    p = _pin_paths()
    sha = _git("rev-parse", "HEAD").stdout.strip()
    if not os.path.exists(p["latest"]):
        print("testmgr --pin: no %s yet — run `make stabilize-fast` first"
              % os.path.relpath(p["latest"], REPO), file=sys.stderr)
        return 1
    dirty = _git("status", "--porcelain", "--", "compiler/").stdout.strip()
    if dirty and not args.force:
        print("testmgr --pin: compiler/ has uncommitted changes — pinning them "
              "would bless a binary built from sources nobody can check out:\n%s"
              % dirty[:500], file=sys.stderr)
        print("         commit them, or --force if you mean it.", file=sys.stderr)
        return 1

    # Resumability is cheap because the expensive half is skippable, not
    # because the pin is checkpointed: a gate that already passed for THIS sha
    # with a clean tree does not need re-running, and stabilize-fast is ~35s.
    # (stabilize-fast, not stabilize -- user, 2026-08-09: all-target
    # verification belongs to a RELEASE, not to a pin.)
    state_path = os.path.join(REPO, PIN_STATE_REL)
    prior = {}
    try:
        with open(state_path) as f:
            prior = json.load(f)
    except (OSError, ValueError):
        pass
    gated = prior.get("gated_sha") == sha and not dirty

    if gated and not args.force:
        print("testmgr --pin: gate already green for %s (%s) — skipping it"
              % (sha[:12], prior.get("gated_at", "?")), flush=True)
    else:
        down = watcher_is_down() if not args.tier else False
        tier = pin_gate_tier(args.tier, down)
        # Say what is about to happen and roughly how long. Silence for minutes
        # is what got the old default killed twice as a hang — a UX defect
        # independent of which tier is correct.
        print("testmgr --pin: gate — tier %s at %s (%s)%s"
              % (tier, sha[:12], PIN_TIER_COST.get(tier, "duration unknown"),
                 "; Track T is DOWN, so nothing else is sweeping the matrix "
                 "— pass --tier quick to override" if down else ""),
              flush=True)
        # A child, so the gate keeps the process-group teardown twatch.kill_child
        # relies on. It INHERITS this process's lock rather than taking one:
        # --force here used to mean "the lock is mine, proceed" and was executed
        # as "kill the holder", i.e. this process
        # (bug-t-testmgr-pin-force-kills-its-own-parent).
        env = dict(os.environ, **{LOCK_INHERIT_ENV: str(os.getpid())})
        rc = subprocess.run([sys.executable, os.path.abspath(__file__),
                             "--tier", tier], cwd=REPO, env=env).returncode
        if rc != 0:
            print("testmgr --pin: gate RED (rc %d) — nothing pinned, tree "
                  "untouched" % rc, file=sys.stderr)
            return rc
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        with open(state_path, "w") as f:
            json.dump({"gated_sha": sha, "gated_at": utcnow_iso()}, f)
        print("testmgr --pin: gate GREEN", flush=True)

    print("testmgr --pin: stabilize-fast (~40s — self → next → fixedpoint, "
          "byte-identical)", flush=True)
    if subprocess.run(["make", "stabilize-fast"], cwd=REPO).returncode != 0:
        print("testmgr --pin: stabilize-fast FAILED — nothing pinned",
              file=sys.stderr)
        return 1

    print("testmgr --pin: applying the pin (uninterruptible from here — "
          "microseconds)", flush=True)
    newsha, nbuiltin = apply_pin_atomic(p, sha)

    # `make pin` must git-add the stable tree -- a recorded past miss: an
    # automated pin that skips it produces a pin nobody else can see.
    add = _git("add", "-u", STABLE_ROOT_REL)
    if add.returncode != 0:
        print("testmgr --pin: WARNING git add failed: %s" % add.stderr.strip(),
              file=sys.stderr)
    _git("add", STABLE_DEFAULT_REL + "/builtin")
    staged = _git("diff", "--cached", "--name-only", "--",
                  STABLE_ROOT_REL).stdout.split()
    print("testmgr --pin: pinned %s (%d builtin source(s) frozen), %d file(s) "
          "STAGED — commit them, they are the pin"
          % (newsha[:12], nbuiltin, len(staged)), flush=True)
    return 0


def utcnow_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run_bench():
    import socket
    if not build_compiler():
        sys.exit("testmgr: --bench needs a working compiler")
    cc = os.path.join(REPO, COMPILER)
    host = re.sub(r"[^A-Za-z0-9_-]", "-",
                  socket.gethostname().split(".")[0])
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                         capture_output=True, text=True).stdout.strip()[:12]
    date = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    tsv = os.path.join(REPO, BENCH_TSV_REL)
    out_tsv = os.environ.get("TESTMGR_BENCH_TSV", tsv)   # twatch: detached
    prev = bench_prev(tsv, host)                          # checkout writes
    # Disposed via atexit rather than a try/finally around this whole function:
    # run_bench() has several early `return`s, and a bench dir is the single
    # largest /tmp consumer on this box (768 MB across 20 leaked rounds before
    # this was fixed) — on a tmpfs box that is RAM the scheduler is counting on.
    tmp = tempfile.mkdtemp(prefix="tbench-")              # elsewhere
    atexit.register(shutil.rmtree, tmp, ignore_errors=True)
    timeout = 120 * float(os.environ.get("TESTMGR_TIME_SCALE", "1"))
    fpc_present = shutil.which(FPC_BIN) is not None
    if not fpc_present:
        print("  bench: fpc not found — skipping the `fpc` comparison level")
    rows, slow, red, clocks = [], [], [], []
    mhz_max = None
    try:
        with open("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq") as f:
            mhz_max = int(f.read().strip()) / 1000.0
    except (OSError, ValueError):
        pass

    def record(name, lvl, secs, clock=None):
        ms = round(secs * 1000, 1)
        rows.append("%s\t%s\t%s\t%s\t%s\t%s" % (date, host, sha, name, lvl, ms))
        old = prev.get((name, lvl))
        note = ""
        if old and ms > old * (1 + BENCH_SLOW_PCT / 100.0):
            note = "  SLOW (was %sms)" % old
            slow.append("%s %s %s -> %sms" % (name, lvl, old, ms))
        if clock:
            mhz, lo, hi = clock
            clocks.append("%s\t%s\t%s\t%s\t%.0f\t%.0f\t%.0f"
                          % (date, host, name, lvl, mhz, lo, hi))
            # Say it at the time. A row taken off boost is not wrong, but it is
            # not comparable to one taken on boost, and the number alone has
            # never told anyone which it was.
            if mhz_max and mhz < mhz_max * 0.97:
                note += "  [%.0f MHz, %.0f%% of max]" % (mhz, 100.0 * mhz / mhz_max)
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
            dt, clk = bench_time([b] + [a.format(tmp=tmp) for a in timed],
                                 BENCH_RUNS, timeout,
                                 label="%s %s" % (name, lvl))
            if dt is None:
                red.append("%s %s run" % (name, lvl))
                continue
            record(name, lvl, dt, clk)

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
                    dt, clk = bench_time([fb] + [a.format(tmp=tmp)
                                                 for a in timed],
                                         BENCH_RUNS, timeout,
                                         label="%s %s" % (name, FPC_LEVEL))
                    if dt is not None:
                        record(name, FPC_LEVEL, dt, clk)

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
        dt, clk = bench_time([stage, COMPILER_SRC,
                              os.path.join(tmp, "selfout")],
                             BENCH_SELF_RUNS, timeout * 5,
                             label="selfcompile %s" % lvl)
        if dt is None:
            red.append("selfcompile %s run" % lvl)
            continue
        record("selfcompile", lvl, dt, clk)

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
            dt, clk = bench_time(argv, BENCH_SELF_RUNS, timeout * 5,
                                 label="selfcompile %s" % FPC_LEVEL)
            if dt is not None:
                record("selfcompile", FPC_LEVEL, dt, clk)

    if rows:
        os.makedirs(os.path.dirname(out_tsv), exist_ok=True)
        fresh = not os.path.exists(out_tsv) or not os.path.getsize(out_tsv)
        with open(out_tsv, "a") as f:
            if fresh:
                f.write("# date\thost\tsha\tworkload\tlevel\tms\n")
            f.write("\n".join(rows) + "\n")
    if clocks:
        # Same temp-file dance as the rows when running under twatch: the tree
        # is detached there, and both files are tracked.
        out_clk = (out_tsv + ".clock" if out_tsv != tsv
                   else os.path.join(REPO, BENCH_CLOCK_TSV_REL))
        os.makedirs(os.path.dirname(out_clk), exist_ok=True)
        fresh = not os.path.exists(out_clk) or not os.path.getsize(out_clk)
        with open(out_clk, "a") as f:
            if fresh:
                f.write("# date\thost\tworkload\tlevel\tmhz\tmhz_lo\tmhz_hi\n")
            f.write("\n".join(clocks) + "\n")
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
    cap = int(total * SCOPE_MAX_FRAC)
    if cap < SCOPE_MIN_ABS:                 # small box: lift toward the floor,
        cap = min(SCOPE_MIN_ABS, int(total * 0.75))   # but never past 75% of it
    # a shared/small box (twatch limited/restricted profile) can pin a HARD
    # ceiling below the fraction-of-total default, so the watcher never claims
    # more than its share. Only ever LOWERS the cap, never raises it above the
    # box-proportional default.
    mem_cap_mb = os.environ.get("TESTMGR_MEM_CAP_MB")
    if mem_cap_mb:
        try:
            cap = min(cap, int(mem_cap_mb) << 20)
        except ValueError:
            pass
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
    ap.add_argument("--pin", action="store_true",
                    help="gate, stabilize-fast and PIN, as one interruptible "
                         "operation: SIGINT leaves either a completed pin or an "
                         "untouched tree. Operator command on a dev box — the "
                         "watcher daemon never pins (it writes only tstate/)")
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
    ap.add_argument("--force", action="store_true",
                    help="kill a live run in this repo and take over (default is "
                         "to refuse: two runs starve each other on the memory gates)")
    ap.add_argument("--status", action="store_true",
                    help="is a run live in this repo, or anywhere on this box? "
                         "(systemd-scoped runs do NOT appear in pstree)")
    ap.add_argument("--older-than", type=float, default=30, metavar="MIN",
                    help="--kill-orphans: age floor in minutes (default 30)")
    ap.add_argument("--kill-orphans", action="store_true",
                    help="kill every testmgr on this box — the detached runs whose "
                         "shell/agent is gone but which keep running and starving "
                         "new runs")
    args = ap.parse_args()

    if args.status or args.kill_orphans:
        state, info = lock_state()
        if state == "free":
            print("testmgr: no run in THIS repo (%s)" % REPO)
        else:
            ago = int(time.time() - info.get("started", time.time()))
            beat = int(time.time() - info.get("heartbeat", 0))
            print("testmgr: %s run in this repo — pid %d, tier %s, up %dm%02ds, "
                  "heartbeat %ds ago" % (state.upper(), info.get("pid", -1),
                                         info.get("tier", "?"), ago // 60,
                                         ago % 60, beat))
            if state == "stale":
                print("         (stale: the next run reaps it automatically)")

        # Box-wide: these do NOT show up in pstree (systemd-scoped, see
        # find_runs()), so this is the only way anyone can see them.
        runs = find_runs()
        if runs:
            print("\ntestmgr: %d run(s) on this box — NOT visible in pstree "
                  "(systemd-scoped, reparented to pid 1):" % len(runs))
            for pid, repo, tier, age in runs:
                mine = " <- this repo" if repo == REPO else ""
                print("  pid %-8d %-32s tier %-10s up %dm%02ds%s"
                      % (pid, repo, tier, int(age) // 60, int(age) % 60, mine))
            print("\n  An orphan (its agent/shell is gone) keeps running to its "
                  "deadline and holds memory,\n  which starves every new run's "
                  "admission. Reap with: tools/testmgr.py --kill-orphans")
        if args.kill_orphans:
            # "Detached" is NOT "orphaned" -- EVERY scoped run is detached by
            # design, including the twatch daemon's and other agents' live runs.
            # Killing those would be far worse than the leak we are fixing. A run
            # is an orphan only if it is not actually SCHEDULING any more: its own
            # repo's lock has stopped beating. Plus an age floor, so a run that is
            # merely mid-build (heartbeat starts at lock acquisition, but an old
            # testmgr predating locks writes none at all) is never shot on sight.
            n = skipped = 0
            for pid, repo, tier, age in runs:
                if pid == os.getpid():
                    continue
                beat = 0.0
                try:
                    with open(os.path.join(repo, ".testmgr", "run.lock")) as f:
                        beat = json.load(f).get("heartbeat", 0)
                except (OSError, ValueError):
                    pass
                alive = (time.time() - beat) < HEARTBEAT_STALE if beat else False
                if alive:
                    print("  keep  pid %-8d %s — heartbeat fresh, it IS working"
                          % (pid, repo))
                    skipped += 1
                    continue
                if age < args.older_than * 60:
                    print("  keep  pid %-8d %s — only %dm old (< --older-than %dm); "
                          "may be an old testmgr with no lock, or mid-build"
                          % (pid, repo, int(age) // 60, args.older_than))
                    skipped += 1
                    continue
                kill_run(pid, "orphan: no heartbeat, up %dm (%s, tier %s)"
                         % (int(age) // 60, repo, tier))
                n += 1
            print("testmgr: reaped %d, kept %d" % (n, skipped))
        return 0

    if args.pin:
        # The repo lock is held for the WHOLE pin, gate included: a concurrent
        # tier run would rebuild compiler/pascal26 under stabilize-fast's feet.
        if not acquire_lock(args.force):
            return 2
        atexit.register(release_lock)
        # A pin outlives HEARTBEAT_STALE easily (gate + stabilize-fast), and a
        # lock that never beats is reaped as wedged by ANY reader — including,
        # before this, its own gate child. Liveness is a property of the
        # process, so the pin must beat like a tier run does.
        start_heartbeat("pin")
        return run_pin(args)
    if args.bench:
        # deliberately unscoped: --bench appends to the tracked timing series in
        # tstate/bench.tsv, and it is serial, so it was never the thing that ate
        # the box.  Don't perturb a history that spans hundreds of rows.
        return run_bench()
    if not args.tier:
        ap.error("--tier is required (unless --bench or --pin)")

    # --list does no work; TESTMGR_NO_SCOPE=1 is the escape hatch (self-tests)
    if not args.list and os.environ.get("TESTMGR_NO_SCOPE") != "1":
        reexec_scoped()         # does not return if it scopes us

    # One run per repo. Acquired AFTER reexec_scoped (which replaces the
    # process) so the pid in the lock is the one that actually schedules, and
    # before build_compiler() so two runs cannot race on the same binary.
    if not args.list and not acquire_lock(args.force):
        return 2
    atexit.register(release_lock)
    start_heartbeat(args.tier)

    # A compiler we cannot build is a VERDICT, not an absence of one. Exiting
    # rc=1 here made the watcher log "no report — infra problem, not recording a
    # verdict" and move on: the sha stayed untested, nothing went red, nobody was
    # told, and there was nothing to bisect. A broken self-host must be as loud
    # as a broken test — louder, since everything else rests on it.
    if not build_compiler():
        return report_build_failure(args)

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
        unguarded = "\n".join(ln for ln in j.lines
                              if not CORPUS_GUARD_RE.search(ln))
        missing = sorted({m for m in CORPUS_RE.findall(unguarded)
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

    sweep_orphan_tmp()                  # reclaim dead runs' scratch first
    os.makedirs(RUN_TMP, exist_ok=True)
    atexit.register(drop_run_tmp)       # ...and never become one ourselves
    # Snapshot BEFORE calibrate(), so even calibration measures the binary the
    # jobs will actually use. repo_sha0 is kept only to report how often a
    # concurrent rebuild happens — the frequency is the signal that says whether
    # this snapshot and the PXX_TMP split actually fixed the race.
    snap_path, snap_sha = snapshot_compiler()
    repo_sha0 = file_sha256(os.path.join(REPO, "compiler/pascal26"))
    if snap_path:
        print("testmgr: compiler snapshot %s (sha256 %s)"
              % (snap_path, (snap_sha or "?")[:12]), flush=True)
    scale = calibrate()
    # propagate to child scripts with their own inner `timeout` calls
    os.environ["TESTMGR_TIME_SCALE"] = "%.2f" % scale
    os.environ["TESTMGR_TMP"] = RUN_TMP     # for tool scripts' own scratch
    logdir = tempfile.mkdtemp(prefix="testmgr-")
    run_jobs = [j for j in jobs if j.status != "skip"]
    mgr = Manager(run_jobs, args, scale, logdir)
    # Live-concurrency factor for scripts whose INNER per-item timeouts starve
    # under the full parallel matrix (qemu-user conformance shards especially:
    # a single slow program crosses its per-program budget and false-REDs the
    # whole shard with exit 124 — regression-testmgr-conformance-shard-timeout-
    # under-load). TESTMGR_TIME_SCALE is an idle hardware probe and stays ~1 on
    # a fast box, so it never captures this; cap/cores does. Never below 1 (only
    # ever extends a budget, never shortens it).
    os.environ["TESTMGR_LOAD_SCALE"] = "%.2f" % max(
        1.0, mgr.hard_cap / float(os.cpu_count() or 1))
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
                 else "FLAKY" if j.flaky
                 else j.status.upper())
        if j.flaky:
            note += "  (flaked, passed on attempt %d)" % j.attempts
        print("  %-8s %-32s %-12s %6.1fs  %s%s" %
              (state, j.name, j.cls, dur, j.src, note))
        if j.status in ("fail", "timeout") and not j.advisory \
                and first_fail is None:
            first_fail = j
    npass = sum(1 for j in jobs if j.status == "pass")
    flaky = [j.name for j in jobs if j.flaky]
    print("  %d/%d pass%s%s" % (npass, len(jobs) - nskip,
                                ", %d skip (corpus absent)" % nskip if nskip else "",
                                ", %d flaky (passed on retry)" % len(flaky) if flaky else ""))
    if flaky:
        print("  flaky (recovered on retry, NOT red): %s" % " ".join(flaky))
    # Co-tenancy belongs in the REPORT, not just the scrollback: twatch turns
    # this text into a tstate report someone reads days later while deciding
    # whether a red is real. "The box was shared" is the first thing that
    # triage needs and the last thing it used to be told.
    if mgr.peer_repos:
        print("  NOTE this run shared the box with another clone's testmgr "
              "(%s) — long jobs got %.0fx timeouts and kills were retried; "
              "expect longer durations than a solo run"
              % (", ".join(sorted(mgr.peer_repos)), PEER_TIME_FACTOR))
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
    # ---- provenance: did the binary the jobs used change underneath them? ----
    # A run that used binary A for its first 200 jobs and binary B for the rest
    # has no honest single verdict, so it gets INVALID rather than GREEN or RED
    # — a red from a mixed run is exactly as untrustworthy as a green, and
    # auto-filing a regression from one manufactures phantom-red noise.
    snap_sha_end = file_sha256(snap_path) if snap_path else None
    repo_sha1 = file_sha256(os.path.join(REPO, "compiler/pascal26"))
    invalid = bool(snap_path and snap_sha and snap_sha_end
                   and snap_sha != snap_sha_end)
    # With the snapshot in place the repo binary moving is HARMLESS — that is
    # the whole point — so it is reported, not fatal. Without a snapshot it is
    # the real thing and must invalidate.
    repo_moved = bool(repo_sha0 and repo_sha1 and repo_sha0 != repo_sha1)
    if repo_moved and not snap_path:
        invalid = True
    if repo_moved:
        print("testmgr: NOTE compiler/pascal26 changed during this run "
              "(%s -> %s)%s" % (repo_sha0[:12], repo_sha1[:12],
                                " — jobs ran against the snapshot, results stand"
                                if snap_path else ""), flush=True)
    verdict = ("INVALID" if invalid else
               "GREEN" if rc == 0 else
               "INTERRUPTED" if rc == 130 else "RED")
    if invalid:
        print("testmgr: INVALID — the compiler changed mid-run (%s -> %s). "
              "This run's PASS/FAIL cannot be attributed to one binary."
              % ((snap_sha or repo_sha0 or "?")[:12],
                 (snap_sha_end or repo_sha1 or "?")[:12]), flush=True)
    print("\ntestmgr: %s" % verdict)
    if args.report_json:
        rep = {"tier": args.tier, "wall": round(wall, 1), "scale": round(scale, 2),
               "verdict": verdict,
               # the binary these results came from, so a report's provenance is
               # identifiable after the fact instead of inferred from timestamps
               "compiler_sha256": snap_sha or repo_sha0,
               "compiler_changed_mid_run": repo_moved,
               "slow": slow,
               "flaky": [j.name for j in jobs if j.flaky],
               # "sel": the STABLE way to name this job again later (twatch
               # bisects and files tickets on it).  j.name is a positional
               # index that renumbers whenever a test is inserted above it.
               "selfhost_red": mgr.selfhost_red,
               # Only jobs that actually RAN. A self-host abort leaves the rest
               # "skipped" (never launched) — distinct from "skip" (corpus
               # absent, a real pass-equivalent outcome). Emitting them would be
               # wrong in both directions: twatch maps "skip"->pass, so they
               # would either launder into passes or, as the literal "skipped",
               # read as a mass RED. Omitting them lets twatch's merge keep each
               # job's previous verdict, which is the honest answer for a job
               # this run never attempted.
               "jobs": [{"name": j.name, "cls": j.cls, "src": j.src,
                         "sel": j.sel or j.name,
                         "advisory": j.advisory,
                         "status": j.status,
                         "flaky": j.flaky,
                         "attempts": j.attempts,
                         "dur": round((j.t1 - j.t0), 1) if j.t0 and j.t1 else 0.0,
                         "mem": j.peak_rss, "cpu": round(j.cpu_sec, 1),
                         "log": j.logpath}
                        for j in jobs
                        if j.status not in ("queued", "skipped")]}
        with open(args.report_json, "w") as f:
            json.dump(rep, f, indent=1)
    return rc


if __name__ == "__main__":
    sys.exit(main())
