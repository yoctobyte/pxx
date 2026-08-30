#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a row whose subject is the exit code must assert the exit code.

chore-t-sweep-for-rows-that-assert-stdout-when-the-subject-is-an-exit-code.

`Halt(5)` exited 0 on hosted xtensa. `test_halt_exit_code` was IN the
`test-xtensa` target and it **PASSED** — the row compared stdout, which was
correct (`halting with 5`), while the exit code was 0. riscv32's row for the same
program appended `echo "exit=$?"`. Xtensa's was written without it.

frankS's three-way table is why this file exists:

    nothing can execute the target             -> a gap
    the op is missing, the program never runs  -> a gap
    the row runs and asserts the wrong thing   -> a GREEN

The first two leave something visible and somebody eventually asks about the
hole. **The third produces a passing row, and a passing row is a completed
obligation** — its existence is positive evidence that the property is covered,
so nobody revisits it. Ever.

WHAT THIS PINS, and what it deliberately does not. `FAMILY` below is the set of
programs whose SUBJECT is an exit code or a signal — where a particular exit
status is the thing under test, not a way of failing an assertion. Every
`expect_same.sh` row naming one must capture `$?`. That is 10 rows today and all
10 comply; the guard exists so the eleventh cannot be written without it, which
is exactly how the xtensa row got written.

NOT IN THE FAMILY, measured rather than assumed: 32 further rows name a program
containing `Halt(n)` with a nonzero literal, and every one is an assertion
mechanism — `lib_dns_resolve` does `Halt(1)` on failure and `Halt(0)` on success,
`crtl_atexit`'s subject is LIFO handler ORDER and exit() is merely one of the two
paths that must produce it. Their exit code is not the observable, and listing
them would be 32 findings that cost nobody anything — which is how a check earns
the habit of being scrolled past. The narrow family is the point.

THE BIGGER EXPOSURE IS NOT A LIST, and this file does not pretend to close it:
**531 of 536 cross-target differential rows compare stdout only**, and for those
the exit code is free to add (both sides are runs of the same program). frankS's
bug lived in exactly that shape. Section 3 measures it and holds the number, so
it cannot drift upward unnoticed while the family stays green — a guard on the
thing this guard cannot check.

Run: python3 tools/exit_observable_devtest.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MK = (ROOT / "Makefile").read_text(errors="replace").splitlines()
CAPTURE = 'exit=$$?'
fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-62s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


# Programs whose SUBJECT is the exit status or a signal. Explicit, with the
# reason, because a heuristic over `Halt(` cannot tell "the code under test"
# from "how this test fails" and gets 32 wrong.
FAMILY = {
    "test_halt_exit_code":   "Halt(5) — the code IS the assertion",
    "test_halt_exit":        "same program, native row",
    "test_i386_halt":        "same program, i386 row",
    "test_aarch64_halt":     "same program, aarch64 row",
    "test_arm32_halt":       "same program, arm32 row",
    "test_riscv32_halt":     "same program, riscv32 row",
    "test_xtensa_test_halt_exit_code": "same program, xtensa row — the one that lapsed",
    "test_signal_handlers":  "delivery counts AND the status the process ends on",
    "test_signal_altstack":  "recursion on an alternate stack, then the status",
    "test_div_zero_re200":   "runtime error 200 — a nonzero status is the subject",
}


def rows():
    for i, ln in enumerate(MK, 1):
        if "expect_same.sh" in ln:
            yield i, ln


def names(line):
    # The `26` suffix on native binaries (test_halt_exit26) is a word character,
    # so a plain \b after the program name matches nothing -- the first cut of
    # this file found 5 of 10 and reported it as a coverage failure rather than
    # as its own regex. Allow the numeric suffix explicitly.
    return sorted((p for p in FAMILY
                   if re.search(r"[/_ (]%s\d*\b" % re.escape(p), line)),
                  key=len, reverse=True)


def main():
    print("1. every row on an exit-status subject asserts the exit status")
    seen, bad = set(), []
    for i, ln in rows():
        n = names(ln)
        if not n:
            continue
        seen.update(n)          # ALL of them: a row naming test_halt_exit_code
                                # also names test_halt_exit, and attributing
                                # only the longest reported 9 of 10 as a gap
        if CAPTURE not in ln:
            bad.append((i, n[0], ln.strip()[:80]))
    check(not bad, "no row in the family compares stdout alone",
          "; ".join("Makefile:%d %s" % (i, p) for i, p, _ in bad[:3]))
    check(len(seen) == len(FAMILY), "and every family member is reachable in the Makefile",
          "%d of %d programs matched a row" % (len(seen), len(FAMILY)))

    print("2. the guard discriminates — it fails on the row as it was written")
    lapsed = ('\ttools/expect_same.sh xtensa/test_halt_exit_code '
              '"$$(tools/run_target.sh xtensa $(TESTTMP)/test_xtensa_test_halt_exit_code)" '
              '"$$($(TESTTMP)/test_xtensa_test_halt_exit_code_x64)"')
    check(names(lapsed) and CAPTURE not in lapsed,
          "the pre-fix xtensa row is recognised and would be reported",
          "this is the exact line that passed while Halt(5) exited 0")
    fixed = lapsed.replace(")\"", '; echo "exit=$$?")"')
    check(CAPTURE in fixed, "and the fixed form satisfies it")

    print("3. ...and the exposure the family CANNOT cover, held at its measured size")
    cross = [ln for _, ln in rows() if "run_target.sh" in ln and ln.count('"$$(') >= 2]
    capped = [ln for ln in cross if CAPTURE in ln]
    check(len(cross) >= 500, "cross-target differential rows are still ~536",
          "%d" % len(cross))
    check(len(cross) - len(capped) <= 531,
          "and the stdout-only count has not grown past its 2026-08-30 measurement",
          "%d compare stdout alone (was 531)" % (len(cross) - len(capped)))
    check(len(capped) >= 5, "while the ones that do capture are not lost",
          "%d" % len(capped))

    print("4. the family list is honest about its own scope")
    heur = [p for p in FAMILY if "halt" in p or "signal" in p or "div_zero" in p]
    check(len(heur) == len(FAMILY),
          "every member is a halt/signal/runtime-error program, not a lib_* test")
    check(all(v for v in FAMILY.values()),
          "and every member carries the reason it is in the family")

    print("\n  %d guard(s), %d FAIL" % (9, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
