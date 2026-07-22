#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""uforth_bench.py — cross-runtime speed oracle for the NilPy backend.

Track T tool (feature-t-uforth-benchmark-harness). The SAME uforth.py runs on
several runtimes over the SAME Forth workloads, and we report wall-clock +
max-RSS per runtime and the pxx-vs-CPython speedup:

  * cpython     python3 uforth.py            (the interpreter running the source)
  * cpython-O   python3 -O uforth.py         (asserts stripped; cheap column)
  * pypy        pypy uforth.py               (JIT reference, if installed)
  * pxx         <pxx> uforth.py -> native    (our compiled binary)

uforth is a real ~4300-line single-file NilPy program with a large
deterministic workload, which is exactly why it is the natural oracle. Source
lives on GitHub (git@github.com:yoctobyte/uforth); the harness records the
uforth commit sha in every row, so a speed number is tied to a specific source.

T owns the TOOL, never the bug: a slow path found here goes to Track O
(implicitly A) or Track N as a ticket, it is NOT fixed under T.

Rows append to devdocs/progress/tstate/bench.tsv (tab-separated), schema:
    date  host  pxx_sha  workload  level  ms  [uforth_sha]
where `level` is the runtime (cpython / cpython-O / pypy / pxx) so the existing
bench readers keep working and the uforth rows sit alongside the pxx-vs-FPC ones.

Skips CLEANLY (exit 0, a SKIP line) when uforth / python3 / a working pxx is
absent — a bench is not a gate.

Usage:
    tools/uforth_bench.py                 # quick set (no ELF-HASH outlier)
    tools/uforth_bench.py --full          # + blocktest ELF-HASH (~100x slow)
    tools/uforth_bench.py --pxx PATH      # compiler to use (default: repo's)
    tools/uforth_bench.py --uforth DIR    # uforth checkout (default ~/projects/uforth)
    tools/uforth_bench.py --runs N        # clean runs to keep the min of (default 3)
    tools/uforth_bench.py --no-write      # print the table, do not touch bench.tsv
"""

import argparse
import os
import resource
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BENCH_TSV = os.path.join(REPO, "devdocs/progress/tstate/bench.tsv")

# Discard a run whose wall badly exceeds its CPU time — it was descheduled by
# other load, so the number is contamination, not the program's speed. Same
# discipline as testmgr's bench_time.
CPU_WALL_MAX = 1.4          # wall must be <= cpu * this to count as clean
CPU_MIN_S = 0.3             # ...only judged once cpu is big enough to be signal
EXTRA_TRIES = 3             # attempts beyond --runs before giving up on clean


def sh(args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True)


def uforth_sha(uforth_dir):
    r = sh(["git", "-C", uforth_dir, "rev-parse", "--short", "HEAD"])
    return r.stdout.strip() if r.returncode == 0 else "nogit"


def uforth_fetch_state(uforth_dir):
    """Fetch origin (no merge) and report how far behind GitHub the checkout is,
    so a bench row is never silently taken against stale source. Never fails the
    run — offline is fine, we just note it."""
    sh(["git", "-C", uforth_dir, "fetch", "-q", "origin"])
    br = sh(["git", "-C", uforth_dir, "symbolic-ref", "--short", "HEAD"])
    branch = br.stdout.strip() or "HEAD"
    cnt = sh(["git", "-C", uforth_dir, "rev-list", "--count",
              "HEAD..origin/%s" % branch])
    behind = cnt.stdout.strip() if cnt.returncode == 0 else "?"
    return branch, behind


def pxx_sha():
    r = sh(["git", "-C", REPO, "rev-parse", "--short", "HEAD"])
    return r.stdout.strip() if r.returncode == 0 else "unknown"


def timed_run(argv, cwd, timeout):
    """One run: wall seconds and max-RSS (KB) via wait4, or (None, None) on
    failure/timeout. RSS comes from the child's rusage, so it is the real peak
    of THAT process, not a sampled guess."""
    t0 = time.monotonic()
    try:
        # stdin from /dev/null: some drivers (runtests.fth) prompt for input and
        # would otherwise hang until the timeout. A bench workload must be
        # non-interactive.
        p = subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        return None, None, None
    try:
        _, status, ru = os.wait4(p.pid, 0)
    except Exception:
        return None, None, None
    wall = time.monotonic() - t0
    if timeout and wall > timeout:
        return None, None, None
    if os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0:
        return wall, ru.ru_maxrss, ru.ru_utime + ru.ru_stime
    return None, None, None


def bench_one(argv, cwd, runs, timeout, label):
    """Min wall over `runs` clean runs (descheduled runs discarded), plus the
    max-RSS seen on a clean run. Returns (ms, rss_kb) or (None, None)."""
    best_wall = best_rss = None
    clean = tries = 0
    while clean < runs and tries < runs + EXTRA_TRIES:
        tries += 1
        wall, rss, cpu = timed_run(argv, cwd, timeout)
        if wall is None:
            if tries == 1:
                return None, None          # hard failure, not just noise
            continue
        if cpu is not None and cpu >= CPU_MIN_S and wall > cpu * CPU_WALL_MAX:
            continue                       # descheduled — contaminated
        clean += 1
        if best_wall is None or wall < best_wall:
            best_wall = wall
        if rss is not None and (best_rss is None or rss > best_rss):
            best_rss = rss
    if best_wall is None:
        print("  %-16s NOISY (box busy? kept 0/%d clean)" % (label, runs))
    elif clean < runs:
        print("  %-16s noisy: kept %d/%d clean" % (label, clean, runs))
    return (None if best_wall is None else best_wall * 1000.0), best_rss


# Workloads: (name, script-text or file, full_only). A workload is Forth source
# fed to uforth; it MUST run from the uforth dir (the .UFO stdlib loads
# relative). Kept deterministic and bounded.
MICROBENCH = (
    ": BENCH 0 20000 0 DO DUP 1 LSHIFT OVER XOR SWAP 1 AND XOR LOOP DROP ;\n"
    "BENCH BYE\n"
)


def _write(path, *parts):
    """Concatenate source files/text into one workload file. Several Forth.2012
    suite pieces (core.fr, blocktest.fth) are NOT standalone — they use the
    TESTING harness defined in tester.fr and THROW -13 without it — so the real
    workload is tester + the piece, fed as one script."""
    with open(path, "w") as out:
        for p in parts:
            if os.path.isfile(p):
                with open(p) as f:
                    out.write(f.read())
            else:
                out.write(p)
            out.write("\n")


def discover_workloads(uforth_dir, full, scratch):
    """Return [(name, path, full_only)]. Builds concatenated workload files in
    `scratch` where the suite piece needs the tester preamble. Only includes a
    workload whose sources actually exist, so the set adapts to the checkout."""
    t = os.path.join(uforth_dir, "tests")
    tester = os.path.join(t, "tester.fr")
    wl = []

    mb = os.path.join(scratch, "micro.fr")
    _write(mb, MICROBENCH)
    wl.append(("microbench-doloop", mb, False))

    prelim = os.path.join(t, "prelimtest.fth")
    if os.path.isfile(prelim):
        wl.append(("prelim", prelim, False))

    core = os.path.join(t, "core.fr")
    if os.path.isfile(tester) and os.path.isfile(core):
        p = os.path.join(scratch, "core.fr")
        _write(p, tester, core)
        wl.append(("core", p, False))

    # ELF-HASH: the tracked ~100x outlier (blocktest's hash section). Needs the
    # tester preamble too. full runs only — it dominates wall time.
    blk = os.path.join(t, "blocktest.fth")
    if os.path.isfile(tester) and os.path.isfile(blk):
        p = os.path.join(scratch, "elfhash.fr")
        _write(p, tester, blk)
        wl.append(("blocktest-elfhash", p, True))

    return [w for w in wl if full or not w[2]]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pxx", default=os.path.join(REPO, "compiler/pascal26"),
                    help="pxx compiler binary (default: repo compiler/pascal26)")
    ap.add_argument("--uforth",
                    default=os.path.expanduser("~/projects/uforth"))
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=300.0)
    ap.add_argument("--full", action="store_true",
                    help="include the ELF-HASH ~100x outlier")
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()

    ufpy = os.path.join(args.uforth, "uforth.py")
    if not os.path.isfile(ufpy):
        print("uforth-bench: SKIP — no uforth.py at %s "
              "(git clone git@github.com:yoctobyte/uforth %s)"
              % (args.uforth, args.uforth))
        return 0
    if not shutil.which("python3"):
        print("uforth-bench: SKIP — python3 not found")
        return 0

    # runtimes: (level-name, argv-prefix). pxx is added after a successful build.
    runtimes = [("cpython", ["python3"])]
    if os.path.isdir(args.uforth):
        # python3 -O is free; pypy only if installed
        runtimes.append(("cpython-O", ["python3", "-O"]))
    if shutil.which("pypy"):
        runtimes.append(("pypy", ["pypy"]))
    elif shutil.which("pypy3"):
        runtimes.append(("pypy", ["pypy3"]))

    # build the pxx native binary once
    pxx_native = None
    if os.path.isfile(args.pxx) and os.access(args.pxx, os.X_OK):
        out = os.path.join("/tmp", "uforth_bench_native_%d" % os.getpid())
        r = sh([args.pxx, ufpy, out])
        if r.returncode == 0 and os.path.exists(out):
            pxx_native = out
        else:
            tail = (r.stdout + r.stderr).strip().splitlines()
            print("uforth-bench: pxx did NOT compile uforth.py — pxx column "
                  "skipped. First error: %s"
                  % (tail[0] if tail else "(no output)"))
    else:
        print("uforth-bench: no usable pxx at %s — pxx column skipped"
              % args.pxx)

    usha = uforth_sha(args.uforth)
    branch, behind = uforth_fetch_state(args.uforth)
    if behind not in ("0", "?"):
        print("uforth-bench: NOTE — uforth checkout is %s commit(s) behind "
              "origin/%s; benching %s. `git -C %s pull` for the latest source."
              % (behind, branch, usha, args.uforth))

    import tempfile
    scratch = tempfile.mkdtemp(prefix="uforth-bench-")
    workloads = discover_workloads(args.uforth, args.full, scratch)
    psha = pxx_sha()
    host = os.uname().nodename
    date = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    rows = []            # (workload, level, ms, rss_kb)
    print("\nuforth-bench @ uforth %s (%s), pxx %s, host %s"
          % (usha, branch, psha, host))
    print("  runtimes: %s%s"
          % (", ".join(n for n, _ in runtimes),
             ", pxx" if pxx_native else ""))
    for wname, wpath, _ in workloads:
        print("\n%s:" % wname)
        # Probe the base runtime first. If cpython cannot run the workload
        # (e.g. a suite piece needing preamble we did not assemble), SKIP the
        # whole workload with a reason rather than emitting partial, speedup-
        # less rows that quietly imply it was measured.
        base_ms, base_rss = bench_one(["python3", ufpy, wpath], args.uforth,
                                      args.runs, args.timeout, "cpython")
        if base_ms is None:
            print("  SKIP — cpython could not run this workload "
                  "(missing preamble, or errored); nothing recorded")
            continue
        rows.append((wname, "cpython", base_ms, base_rss))
        print("  %-16s %9.1f ms   %7.1f MB" % ("cpython", base_ms,
                                               (base_rss or 0) / 1024))
        for level, prefix in runtimes:
            if level == "cpython":
                continue
            ms, rss = bench_one(prefix + [ufpy, wpath], args.uforth,
                                args.runs, args.timeout, level)
            if ms is None:
                continue
            rows.append((wname, level, ms, rss))
            print("  %-16s %9.1f ms   %7.1f MB" % (level, ms, (rss or 0) / 1024))
        if pxx_native:
            ms, rss = bench_one([pxx_native, wpath], args.uforth,
                                args.runs, args.timeout, "pxx")
            if ms is not None:
                rows.append((wname, "pxx", ms, rss))
                speed = (" (%.2fx vs cpython)" % (base_ms / ms)
                         if base_ms and ms else "")
                print("  %-16s %9.1f ms   %7.1f MB%s"
                      % ("pxx", ms, (rss or 0) / 1024, speed))

    # cleanup temp artifacts
    if pxx_native and os.path.exists(pxx_native):
        os.unlink(pxx_native)
    shutil.rmtree(scratch, ignore_errors=True)

    if not rows:
        print("\nuforth-bench: no rows produced (all runtimes failed?)")
        return 1

    if not args.no_write:
        new = not os.path.exists(BENCH_TSV)
        with open(BENCH_TSV, "a") as f:
            if new:
                f.write("# date\thost\tsha\tworkload\tlevel\tms"
                        "\tuforth_sha\trss_kb\n")
            for wname, level, ms, rss in rows:
                f.write("%s\t%s\t%s\tuforth-%s\t%s\t%.1f\t%s\t%d\n"
                        % (date, host, psha, wname, level, ms, usha,
                           rss or 0))
        print("\nwrote %d rows -> %s" % (len(rows), BENCH_TSV))
    else:
        print("\n--no-write: %d rows not persisted" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
