#!/usr/bin/env python3
"""The sqlite-threads inner run budget must stay strictly under its OUTER one.

run_sqlite_thread_test.sh bounds its own run with `timeout`; testmgr bounds the
whole job with the `qemu` class timeout. Two budgets, in two files, that nothing
compared -- and the collision was EXACT: the base aarch64 budget is 120s and
TESTMGR_LOAD_SCALE is ~2.00 at default width, so the sibling formula
`t * time_scale * load_scale` lands on 240, which IS the class outer.

Why that matters more than a few seconds either way: when the outer wins, the
job-level kill reports only "TIMED OUT" and discards the elapsed/budget/scale
line the runner prints. We would have spent the diagnostic in order to buy the
budget -- and that diagnostic is the only reason anyone knows this job was a
timeout rather than a miscompile (it was read as a miscompile for two days).

So this reads BOTH numbers from their real files. Changing either one alone
cannot silently recreate the collision.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = os.path.join(HERE, "run_sqlite_thread_test.sh")
TESTMGR = os.path.join(HERE, "testmgr.py")

FAILS = []


def check(name, cond, detail=""):
    print("  %-4s %s%s" % ("ok" if cond else "FAIL", name,
                           "" if cond else "  <- " + detail))
    if not cond:
        FAILS.append(name)


def runner_text():
    with open(RUNNER, encoding="utf-8") as f:
        return f.read()


def inner_cap():
    m = re.search(r"^INNER_CAP=(\d+)", runner_text(), re.M)
    return int(m.group(1)) if m else None


def base_budgets():
    """{arch: run_to} from the case block — the UNSCALED starting points."""
    out = {}
    for m in re.finditer(r"^\s*(\w+)\)\s+tgt=.*?run_to=(\d+)", runner_text(), re.M):
        out[m.group(1)] = int(m.group(2))
    return out


def qemu_outer():
    with open(TESTMGR, encoding="utf-8") as f:
        m = re.search(r'"qemu":\s*\{[^}]*"timeout":\s*(\d+)', f.read())
    return int(m.group(1)) if m else None


def scaled(base, s, l, cap):
    v = base * s * l
    if v < base:
        v = base
    if v > cap:
        v = cap
    return int(v)


def main():
    cap, outer, bases = inner_cap(), qemu_outer(), base_budgets()

    print("both numbers are readable, or this guard is asserting nothing")
    check("INNER_CAP found in the runner", cap is not None, "regex drifted")
    check("qemu class timeout found in testmgr.py", outer is not None,
          "the CLASSES table moved")
    check("per-arch base budgets found", len(bases) >= 4, bases)
    if cap is None or outer is None or not bases:
        print("\nFAILED: cannot read the constants — fix the parse first")
        return 1
    print("     (INNER_CAP=%ds, qemu outer=%ds, bases=%s)" % (cap, outer, bases))

    print("the invariant")
    check("the cap is strictly under the outer", cap < outer,
          "cap=%d outer=%d — the outer would pre-empt and eat the diagnostic"
          % (cap, outer))
    check("...with real headroom, not one second", outer - cap >= 20,
          "gap is only %ds" % (outer - cap))

    print("no reachable scale can push a budget to the outer")
    worst = 0
    for arch, base in sorted(bases.items()):
        for s in (1.0, 2.0, 5.0, 20.0):
            for l in (1.0, 2.0, 4.0, 16.0):
                worst = max(worst, scaled(base, s, l, cap))
    check("the worst budget over a wide scale sweep is still under the outer",
          worst < outer, "worst=%ds outer=%ds" % (worst, outer))

    print("the case this MUST reject — without it the check cannot fail")
    bad = scaled(120, 1.0, 2.0, 10 ** 9)     # the cap removed
    check("uncapped, the sibling formula DOES hit the outer", bad >= outer,
          "expected the historical collision at 120*1*2=240, got %d" % bad)
    check("...so the cap is load-bearing, not decorative", bad > cap,
          "uncapped=%d cap=%d" % (bad, cap))

    print("and it must still STRETCH — a cap that pins it to the base is no fix")
    at_sweep = scaled(bases.get("aarch64", 120), 1.0, 2.0, cap)
    check("under a default sweep aarch64 gets more than its base",
          at_sweep > bases.get("aarch64", 120),
          "%ds vs base %ds" % (at_sweep, bases.get("aarch64", 120)))
    check("a serial make run is unchanged (both scales neutral)",
          scaled(bases.get("aarch64", 120), 1.0, 1.0, cap)
          == bases.get("aarch64", 120), "serial budget moved")

    print("the runner actually multiplies by BOTH scales")
    txt = runner_text()
    check("TESTMGR_LOAD_SCALE is read", "TESTMGR_LOAD_SCALE" in txt)
    check("...and reaches the awk expression, not just the message",
          re.search(r"-v l=\"\$LOAD\"", txt) is not None,
          "LOAD is printed but never applied — the exact misread this fixes")

    print()
    if FAILS:
        print("FAILED %d check(s): %s" % (len(FAILS), ", ".join(FAILS)))
        return 1
    print("all sqlite inner-budget guards green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
