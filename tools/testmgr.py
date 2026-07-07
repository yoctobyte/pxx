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
  tools/testmgr.py --tier quick|limited|full [--jobs N] [--serial]
                   [--fail-fast] [--list] [--deadline SECS]
                   [--inject-hang]   # self-test: prove hang handling
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
}

# The conformance battery (~220 programs behind one script) is a wall-time
# pole as a single job: fan it out with the script's --shard support.
CONFORMANCE_SHARDS = 6

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
}
MEM_FLOOR = 1500 << 20          # never admit below this MemAvailable
PROBE_REF = 0.35                # seconds: hello.pas compile on reference box
TICK = 0.5

COMPILE_RE = re.compile(r"^\.?/?" + re.escape(COMPILER) + r"\b")


class Job:
    def __init__(self, target, index, lines):
        self.target = target
        self.index = index
        self.lines = lines
        self.cls = classify(lines)
        # exclusive resources: two xvfb-run jobs race on the same X display
        self.resources = {"xvfb"} if "xvfb-run" in "\n".join(lines) else set()
        self.name = "%s#%02d" % (target, index)
        self.deps = []            # jobs that must PASS before this launches
        self.proc = None
        self.t0 = self.t1 = None
        self.timeout = None       # set after calibration
        self.status = "queued"    # queued|running|pass|fail|timeout|skipped
        self.logpath = None
        self.requeued = False

    def script(self):
        # Emulate make exactly: each logical recipe line is judged by ITS
        # overall exit status (last command) — no `set -e`, which would abort
        # mid-line on intermediate nonzero rc (`bin; test "$?" = "20"`).
        parts = ["cd %s || exit 1" % shlex.quote(REPO)]
        for ln in self.lines:
            if ln.strip().startswith("#"):
                continue                      # recipe comment: shell no-op
            parts.append("{\n%s\n} || exit $?" % ln)
        return "\n".join(parts) + "\n"


def classify(lines):
    text = "\n".join(lines)
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
        # launch longest-expected jobs first: the critical path (corpus,
        # conformance shards, selfhost chains) must start at t=0, not after
        # 600 unit jobs have churned through.  Report order stays generation
        # order — this only affects launch order.
        self.queue = sorted(jobs, key=lambda j: -CLASSES[j.cls]["timeout"])
        self.nproc = os.cpu_count() or 1
        self.hard_cap = 1 if args.serial else (
            args.jobs or min(self.nproc,
                             max(1, (mem_available() - MEM_FLOOR) // (800 << 20))))
        self.prev_cpu = cpu_times()
        self.idle_frac = 1.0
        self.interrupted = False
        self.deadline = time.monotonic() + args.deadline
        for j in jobs:
            if j.timeout is None:
                j.timeout = CLASSES[j.cls]["timeout"] * scale

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

    def admit_ok(self, job, now):
        if len(self.running) >= self.hard_cap:
            return False
        if job.resources and any(job.resources & r.resources for r in self.running):
            return False
        if self.running and self.idle_frac < 0.10:
            return False
        # charge est_mem for jobs too young for their RSS to show up yet
        uncharged = sum(CLASSES[j.cls]["est_mem"]
                        for j in self.running if now - j.t0 < 5.0)
        avail = mem_available() - uncharged
        return avail - CLASSES[job.cls]["est_mem"] > MEM_FLOOR

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
                        "/tmp/testmgr_probe26"], cwd=REPO,
                       capture_output=True)
    dt = time.monotonic() - t0
    if r.returncode != 0:
        sys.exit("testmgr: probe compile failed — is %s healthy?" % COMPILER)
    return max(1.0, dt / PROBE_REF)


def build_compiler():
    r = subprocess.run(["make", "--no-print-directory", COMPILER], cwd=REPO)
    if r.returncode != 0:
        sys.exit("testmgr: building %s failed" % COMPILER)


# ------------------------------------------------------------------ main ---
def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tier", choices=sorted(TIERS), required=True)
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

    build_compiler()
    jobs = generate(args.tier)
    if args.job:
        jobs = [j for j in jobs if fnmatch.fnmatch(j.name, args.job)]
        if not jobs:
            sys.exit("testmgr: no jobs match --job %r" % args.job)
        for j in jobs:      # deps may have been filtered out: drop them
            j.deps = [d for d in j.deps if d in jobs]
    if args.inject_hang:
        hang = Job("injected-hang", 0, ["while :; do :; done"])
        hang.cls = "unit"
        hang.timeout = 10       # small: prove the per-job timeout kill path
        jobs.append(hang)

    if args.list:
        for j in jobs:
            print("%-32s %-12s %2d lines%s" %
                  (j.name, j.cls, len(j.lines),
                   "  deps:" + ",".join(d.name for d in j.deps) if j.deps else ""))
        print("total: %d jobs" % len(jobs))
        return 0

    scale = calibrate()
    # propagate to child scripts with their own inner `timeout` calls
    os.environ["TESTMGR_TIME_SCALE"] = "%.2f" % scale
    logdir = tempfile.mkdtemp(prefix="testmgr-")
    mgr = Manager(jobs, args, scale, logdir)
    print("testmgr: tier=%s jobs=%d cap=%d scale=%.2f logs=%s"
          % (args.tier, len(jobs), mgr.hard_cap, scale, logdir), flush=True)
    t0 = time.monotonic()
    rc = mgr.run()
    wall = time.monotonic() - t0

    # ---- deterministic fixed-order report ----
    print("\n== testmgr report (tier %s, %.1fs wall) ==" % (args.tier, wall))
    first_fail = None
    for j in jobs:                       # generation order == report order
        dur = (j.t1 - j.t0) if j.t0 and j.t1 else 0.0
        print("  %-8s %-32s %-12s %6.1fs" % (j.status.upper(), j.name, j.cls, dur))
        if j.status in ("fail", "timeout") and first_fail is None:
            first_fail = j
    npass = sum(1 for j in jobs if j.status == "pass")
    print("  %d/%d pass" % (npass, len(jobs)))
    if first_fail:
        print("\n-- first failure: %s (%s) --" % (first_fail.name, first_fail.status))
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
               "jobs": [{"name": j.name, "cls": j.cls, "status": j.status,
                         "dur": round((j.t1 - j.t0), 1) if j.t0 and j.t1 else 0.0,
                         "log": j.logpath}
                        for j in jobs]}
        with open(args.report_json, "w") as f:
            json.dump(rep, f, indent=1)
    return rc


if __name__ == "__main__":
    sys.exit(main())
