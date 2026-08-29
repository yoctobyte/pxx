#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the calibration probe has range, and says so when it does not.

calibrate() exists so weak hardware never gets false timeouts. For the life of
the function it did not work, and nothing said so: it timed one `hello.pas`
compile against a 0.35s reference, and measured 0.25-0.27s on plexus (2013 Ivy
Bridge) -> max(1.0, 0.74) = 1.0. `seven` -- a 2010 Westmere with no AVX --
published `scale: 1.0` in its own reports too. Two boxes a decade apart received
byte-identical budgets, and two jobs that had never once passed on the slower one
timed out 0.4% over budget and were swept into an 18-job cascade filed against
twelve innocent commits (rejected/regression-cascade-154d1aa3fba6).

It was never a floor problem -- the floor is right, a budget must never shrink
below the reference box. It is RESOLUTION: a 0.26s single-threaded compile is
mostly process startup and has ~1.3x of range across a decade, while the budgets
it scales govern qemu-user emulation, where the same two boxes are much further
apart and where the false timeouts actually landed.

Guards:

  1. two probes, combined with max() -- either axis may raise the budget.
  2. the floor holds: a fast box gets 1.0, never less.
  3. an absent emulator is NO OPINION, not "fast". Every failure path in
     calibrate_emulated() returns None, because a small number reported by a
     probe that measured nothing silently withholds the only evidence that
     would have raised a budget.
  4. a cross-compile that fails, and a run that exits nonzero, are also None.
  5. the scale line is printed AT THE FLOOR TOO. "The floor is the answer" is
     exactly what went unnoticed for the life of this function, and a line that
     appears only when the probe found something cannot report finding nothing.

Honesty about what these are: guards 1(emulated), 3, 4, 5 and 6 cover behaviour
that did not exist before this change, so they cannot be shown to discriminate
against the old code -- it has no `calibrate_emulated`, no PROBE_EMU_* and prints
nothing, and the module would not even import under them. Guard 2 is a plain
regression pin on the floor, which is pre-existing and must not move. Read this
file as "15 checks on new behaviour plus one pin", never as 15 witnesses.

Run: python3 tools/testmgr_calibrate_range_devtest.py
"""

import io
import os
import sys
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr as tm  # noqa: E402

fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-58s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


class R:
    def __init__(self, rc=0):
        self.returncode = rc
        self.stdout = self.stderr = b""


def run_calibrate(native_secs, emulated_ratio):
    """calibrate() with both probes replaced. -> (scale, printed text)."""
    real_run, real_emu, real_clock = tm.subprocess.run, tm.calibrate_emulated, tm.time.monotonic
    ticks = iter([0.0, native_secs])
    try:
        tm.subprocess.run = lambda *a, **k: R(0)
        tm.calibrate_emulated = lambda: emulated_ratio
        tm.time.monotonic = lambda: next(ticks)
        buf = io.StringIO()
        with redirect_stdout(buf):
            scale = tm.calibrate()
        return scale, buf.getvalue()
    finally:
        tm.subprocess.run, tm.calibrate_emulated, tm.time.monotonic = \
            real_run, real_emu, real_clock


def main():
    print("1. either probe may raise the budget; max() combines them")
    s, _ = run_calibrate(tm.PROBE_REF * 3.0, 1.0)
    check(abs(s - 3.0) < 1e-6, "a slow NATIVE probe raises it", "scale=%.2f" % s)
    s, _ = run_calibrate(tm.PROBE_REF * 0.5, 2.5)
    check(abs(s - 2.5) < 1e-6, "a slow EMULATED probe raises it", "scale=%.2f" % s)
    s, _ = run_calibrate(tm.PROBE_REF * 4.0, 2.5)
    check(abs(s - 4.0) < 1e-6, "the LARGER of the two wins", "scale=%.2f" % s)

    print("2. the floor holds")
    s, _ = run_calibrate(tm.PROBE_REF * 0.4, 0.7)
    check(s == 1.0, "a box faster than the reference gets exactly 1.0")
    s, _ = run_calibrate(tm.PROBE_REF * 0.4, None)
    check(s == 1.0, "...and so does one whose emulated probe had no opinion")

    print("3. an absent emulator is NO OPINION, not zero and not fast")
    real = tm.shutil.which
    try:
        tm.shutil.which = lambda exe: None
        check(tm.calibrate_emulated() is None, "no emulator on PATH -> None")
    finally:
        tm.shutil.which = real
    s, _ = run_calibrate(tm.PROBE_REF * 2.0, None)
    check(abs(s - 2.0) < 1e-6,
          "None does not drag the max down", "scale=%.2f" % s)

    print("4. every other failure path is None too")
    real_which, real_run = tm.shutil.which, tm.subprocess.run
    try:
        tm.shutil.which = lambda exe: "/usr/bin/" + exe
        tm.subprocess.run = lambda *a, **k: R(1)          # cross-compile fails
        check(tm.calibrate_emulated() is None, "a failing cross-compile -> None")
        calls = []

        def run(*a, **k):
            calls.append(a)
            return R(0 if len(calls) == 1 else 2)          # run exits nonzero
        tm.subprocess.run = run
        check(tm.calibrate_emulated() is None, "a nonzero emulated run -> None")
    finally:
        tm.shutil.which, tm.subprocess.run = real_which, real_run

    print("5. the scale line is printed at the floor too")
    s, out = run_calibrate(tm.PROBE_REF * 0.4, 0.7)
    check("x1.00" in out, "it prints the scale it chose", out.strip()[:70])
    check("floor" in out, "and SAYS that the floor is what answered")
    check("no opinion" in run_calibrate(tm.PROBE_REF, None)[1],
          "an absent emulated probe is named in the line, not omitted")
    s, out = run_calibrate(tm.PROBE_REF * 3.0, 1.0)
    check("floor" not in out and "x3.00" in out,
          "a raised budget does not claim to be at the floor")

    print("6. the generated probe source is a probe, not a test")
    check("test/" not in tm.PROBE_EMU_SRC and "program probe_loop" in tm.PROBE_EMU_SRC,
          "it is generated, so nothing can sweep or enrol it")
    check(str(tm.PROBE_EMU_ITERS) in tm.PROBE_EMU_SRC,
          "and its cost is the constant, not a literal that drifted from it")

    print("7. the ratios TRAVEL WITH THE VERDICT, not just to stdout")
    import twatch as tw                                      # noqa: E402
    s, _ = run_calibrate(tm.PROBE_REF * 2.0, 1.3)
    check(tm.PROBE_RATIOS["native"] == 2.0 and tm.PROBE_RATIOS["emulated"] == 1.3,
          "calibrate() records both components", str(tm.PROBE_RATIOS))
    check(tw.probe_line({"native": 2.0, "emulated": 1.3}) == "native=2.00 emulated=1.30",
          "and the report header renders them")
    check(tw.probe_line({"native": 1.4, "emulated": None})
          == "native=1.40 emulated=no opinion",
          "a probe that declined renders as declined, not as 0")
    check(tw.probe_line(None) == "unpublished (older harness)",
          "and a report from before this change says so, rather than lying")
    run_calibrate(tm.PROBE_REF * 0.5, None)
    check(tm.PROBE_RATIOS["emulated"] is None,
          "None survives into the record instead of becoming a number")

    print("\n  %d guard(s), %d FAIL" % (20, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
