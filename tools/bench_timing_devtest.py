#!/usr/bin/env python3
"""Devtest for bench timing resolution (bug-t-bench-sub-second-timings-
quantized-to-50ms).

The bug: `subprocess.run(..., timeout=N)` makes CPython WAIT BY POLLING —
0.5 ms, doubling, capped at 50 ms — so the measured wall time is the first poll
wakeup after the child exited, not the exit. Every sub-second benchmark landed
on the cumulative wakeup schedule

    0.5  1.5  3.5  7.5  15.5  31.5  63.5  113.5  163.5  213.5  263.5 ...

which is the "50 ms grid with a ~14 ms offset" seen in bench.tsv. 61% of rows
are sub-second, so most of the series carried up to ±50 ms of clock artefact.

The gate is a workload of KNOWN duration, chosen to sit between two grid points:
the old path must snap to the grid, the new one must report the truth.
No compiler, no repo state — a busy-waiting python child.
"""
import os
import subprocess
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testmgr  # noqa: E402

TARGET_MS = 70.0          # between the 63.5 and 113.5 wakeups, on purpose
GRID = (31.5, 63.5, 113.5, 163.5, 213.5, 263.5, 313.5)
# a busy loop, not a sleep: sleeping would be reaped by the poller identically
# but would not exercise the cpu/wall contention check that runs beside it
CHILD = ("import time\n"
         "end = time.monotonic() + %f\n"
         "while time.monotonic() < end: pass\n" % (TARGET_MS / 1000.0))

fails = []


def check(name, cond, got=""):
    print(("  ok   " if cond else "  FAIL ") + name +
          (("  got: %s" % got) if not cond and got else ""))
    if not cond:
        fails.append(name)


def near_grid(ms, tol=2.0):
    return any(abs(ms - g) < tol for g in GRID)


def old_style_run(argv, timeout):
    """What bench_time used to do."""
    import time
    t0 = time.monotonic()
    subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=timeout)
    return (time.monotonic() - t0) * 1000.0


def main():
    argv = [sys.executable, "-c", CHILD]

    old = [old_style_run(argv, 30) for _ in range(5)]
    new = []
    for _ in range(5):
        # _timed_run grew a fifth field (task_mhz) — unpack by slice so the
        # next addition does not break this test again for a reason that has
        # nothing to do with what it measures.
        wall, cpu, rc, rss = testmgr._timed_run(argv, 30)[:4]
        new.append(wall * 1000.0)
    print("  target %.1f ms" % TARGET_MS)
    print("  old (subprocess.run timeout=): %s" % [round(v, 1) for v in old])
    print("  new (os.wait4 blocking):       %s" % [round(v, 1) for v in new])

    # Self-calibrating: the child is a busy loop plus an interpreter startup we
    # do not get to choose, so the true duration is whatever the honest clock
    # says. The claim under test is not "the workload takes X" — it is "the old
    # path reports a POLL WAKEUP and the new one reports the exit".
    truth = min(new)
    wakeup = next((g for g in GRID if g >= truth), None)
    print("  true duration ~%.1f ms; next poll wakeup at %.1f ms" % (truth, wakeup))

    # This used to assert `max(old) - min(old) < 3.0` — a SPREAD, which measures
    # the machine and not the code. Caught red on 2026-08-19 at load average 14
    # (the watcher running a full tier on the same box): samples came back
    # [117.4, 166.1, 115.8, 116.0, 116.0], one scheduling stall in five, and the
    # guard failed while the claim it names was still true — min(old) was 2.3 ms
    # from the grid point, exactly as the bug predicts.
    #
    # The grid claim does not need a spread. A stall can only push a sample to a
    # LATER poll wakeup, never off the schedule, so "most samples sit on a grid
    # point" is the same statement made about the code. A continuous clock puts
    # none of them there (the new path scores 0/5), so it still discriminates.
    on_grid = sum(1 for v in old if near_grid(v, 4.0))
    check("the old path snaps to ONE poll wakeup, not the duration",
          on_grid >= 4 and abs(min(old) - wakeup) < 4.0,
          "%d/5 on the grid; min %.1f is %+.1f from %.1f"
          % (on_grid, min(old), min(old) - wakeup, wakeup))
    check("the old path overstates the truth by most of a grid step",
          min(old) - truth > 8.0, round(min(old) - truth, 1))
    check("the new path is not pinned to that wakeup",
          abs(min(new) - wakeup) > 4.0, round(min(new), 1))
    check("the new path varies continuously (a clock, not a grid)",
          len({round(v) for v in new}) > 1, [round(v, 1) for v in new])

    wall, cpu, rc, rss = testmgr._timed_run(argv, 30)[:4]
    check("rusage comes back with it: cpu ~= wall for a busy loop",
          cpu is not None and 0.5 < cpu / wall < 1.5, "cpu=%s wall=%s" % (cpu, wall))
    check("rusage comes back with it: peak RSS is plausible",
          rss and rss > 1000, rss)
    check("exit code is reported", rc == 0, rc)

    # a workload that fails must not be reported as a timing
    bad = testmgr._timed_run([sys.executable, "-c", "raise SystemExit(3)"], 30)
    check("a failing workload reports its non-zero rc", bad[2] == 3, bad)
    # and a hang must be bounded by the watchdog, not measured
    hung = testmgr._timed_run([sys.executable, "-c",
                               "import time; time.sleep(30)"], 1.0)
    check("a hung workload times out to None rather than a number",
          hung[0] is None, hung)

    print()
    print("FAILED: " + ", ".join(fails) if fails else "all bench-timing cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
