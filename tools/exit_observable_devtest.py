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
905 of 958 cross-target differential rows compare stdout only (2026-09-04), and
frankS's bug lived in exactly that shape. Section 3 REPORTS that number and
does not gate on it. It gates on the other direction — the captures already
earned may not be given back — because that is the half a growing corpus cannot
move.

The drift half was tried twice and failed twice, and the reason is worth
keeping. As an absolute COUNT it went red on 2026-09-01 when the corpus grew
536 -> 665 while GETTING BETTER (5 capturing rows became 46). Re-armed as a
SHARE with a positive control proving one more uncapped row would breach it, it
went red again on 2026-09-02 and on 2026-09-04. A bound one row breaches has
zero marginal headroom, and this corpus gains ~20 uncapped rows an hour from
five lanes — so it could not survive a single commit, and capping rows to
satisfy it buys a green the next push takes back. Three firings, three times
the cause was growth, never a lost capture; three RED tiers for it. Closing the
exposure is real work and it is RANKED work, deliberately low: see
`chore-t-make-every-cross-target-row-assert-the-exit-code` [T p45], which
records that run_target.sh returns the EMULATOR's status and that a blanket
rollout manufactures diffs on the rows most worth checking.

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

    print("3. ...and the exposure the family CANNOT cover: the captures already earned")
    cross = [ln for _, ln in rows() if "run_target.sh" in ln and ln.count('"$$(') >= 2]
    capped = [ln for ln in cross if CAPTURE in ln]
    # The LABEL used to say "still ~536" while measuring 561 — a precise number
    # in the prose, 25 out of date, sitting behind a floor 61 below it that
    # could never have noticed. The floor is right and stays: it is a COLLAPSE
    # detector for the population (a parse that stops matching reports zero
    # drift forever), not a ratchet. The drift question belongs to the
    # stdout-only check below, which owns it deliberately. What was wrong was
    # a stated figure nothing re-derived. It now prints the live count and
    # names when the quoted one was taken.
    check(len(cross) >= 500,
          "the cross-target differential population is intact "
          "(536 on 2026-08-30 when this was armed; the floor is a collapse "
          "detector, not a ratchet)",
          "%d" % len(cross))
    # THE SHARE RATCHET IS GONE, and it is worth saying exactly why rather
    # than leaving a hole where an assertion was. It was armed at 92.693%
    # (647/698) on 2026-09-02 WITH A POSITIVE CONTROL ASSERTING THAT ONE MORE
    # UNCAPPED ROW WOULD BREACH IT. That control was honest and it was the
    # design: the bound was held tight on purpose.
    #
    # A bound that one new row breaches is a bound with ZERO marginal headroom,
    # and the corpus this measures grows continuously. Measured 2026-09-04 by
    # frankZ, off `git show <sha>:Makefile | grep -c run_target.sh` at six
    # points through one day: 1068 -> 1197 call sites between 06:11 and 17:48,
    # roughly twenty new rows an hour, from five lanes, and essentially all of
    # them uncapped. So the guard could not survive a single commit: capping
    # rows to satisfy it buys a green that the next agent's push takes back.
    # It went red on growth on 2026-09-01 (665 rows), on 2026-09-02 (698) and
    # again now (958) -- three firings, three times the answer was "the corpus
    # grew", zero times "somebody gave a capture back". Three false positives
    # and no true one, at the cost of a RED in the limited and full tiers each
    # time. CLAUDE.md: a gate that cannot pass is not a gate.
    #
    # AND WHAT IT DEMANDED WAS PARKED WORK. Capping these rows is not free,
    # which is the part the share hid: `chore-t-make-every-cross-target-row-
    # assert-the-exit-code` (T, p45, low-prio) records that run_target.sh
    # returns the EMULATOR's status and that signal deaths do not encode
    # identically under qemu-user and a native shell, so a blanket rollout
    # manufactures diffs on exactly the rows most worth checking. It wants a
    # piloted rollout, one arch at a time. A devtest that reds the tier every
    # few hours to demand work the backlog has deliberately ranked low and
    # flagged as hazardous is arguing with the ranker through the test suite.
    #
    # WHAT REPLACES IT IS THE HALF THAT CARRIED THE VALUE: an improvement
    # ratchet. The rows that DO capture may never fall below what has been
    # earned. Growth cannot trip that -- a new uncapped row leaves it
    # untouched -- while the one shape that is a genuine regression, a capture
    # being deleted or rewritten away, still fails it. The share is PRINTED
    # rather than asserted, so the exposure stays visible on every run and is
    # ranked where ranking belongs, in the two live tickets above.
    uncapped = len(cross) - len(capped)
    share = uncapped / max(len(cross), 1)
    check(len(capped) >= 53,
          "the rows that DO capture the exit code have not been given back",
          "%d capture, floor 53 measured 2026-09-04 (was >= 5); %d of %d = "
          "%.2f%% still compare stdout alone, owned by "
          "chore-t-make-every-cross-target-row-assert-the-exit-code [T p45] "
          "and bug-t-run-target-sh-s-exit-code-is-discarded-at-1082-call-sites "
          "[T p65] -- reported here, ranked there"
          % (len(capped), uncapped, len(cross), 100 * share))
    # THE RATCHET'S OWN POSITIVE CONTROL, drawn from the population it is
    # about: take a row that DOES capture, strip the capture the way an edit
    # would, and the floor must stop recognising it. Without this the floor is
    # a number nobody proved can be crossed -- the exact failure this file was
    # written to name, one level up.
    stripped = [ln for ln in cross if ln != capped[0]] + [
        capped[0].replace('; echo "exit=$$?"', "").replace("\\nexit=0", "")
    ] if capped else []
    check(capped and sum(1 for ln in stripped if CAPTURE in ln) == len(capped) - 1,
          "and that floor discriminates — one capture removed drops below it",
          "%d -> %d" % (len(capped),
                        sum(1 for ln in stripped if CAPTURE in ln)))

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
