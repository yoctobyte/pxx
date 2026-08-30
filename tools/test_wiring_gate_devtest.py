#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: THE GATE for tools/check_test_wiring.py — a test nothing runs fails.

The checker has existed since feature-t-fail-when-a-test-file-is-wired-into-no-
build-rule, with 17 guards of its own. Nothing invoked it. `grep -rn
check_test_wiring` returned two Makefile COMMENTS and one mention in
gui_suite.sh — and one of those comments says:

    # The check_test_wiring gate below is what turns it into one.

There was no gate below it, or anywhere. A closing note asserting a property the
tree does not have, and unlike most of that family its cost is measurable: three
more `.npy` subjects (plus two helper units and a repro) accumulated behind that
sentence while it claimed the population was bounded. A comment describing a
guard is not a guard.

WHY HERE AND NOT `make test`, which the ticket suggested. `make test` is not run
by the per-fix loop — CLAUDE.md's hook denies it outright — so a gate there
fires only in Track T's sweep, many commits after the edit that broke it. That
latency IS the defect: a test wired into nothing is invisible, and a check for
it that is also invisible changes nothing. `tools-devtest` globs
`tools/*devtest*.py` and testmgr runs it in BOTH the `quick` and `limited`
tiers, so this fires at roughly the moment the file lands.

WHAT IT IS NOT: a second checker. `check_test_wiring.py` already covers
.pas/.npy/.c/.lua/.fth and reaches `.expected` through its sibling deliberately,
so a missing pair reports once rather than twice. Writing a parallel "is every
.expected referenced" grep — which is what the ticket that led here proposed —
would have shipped a GREEN second checker beside a RED first one, and the new
one's greenness would have read as coverage. This runs the incumbent.

Run: tools/test_wiring_gate_devtest.py   (exit 0 = pass)
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CHECKER = os.path.join(HERE, "check_test_wiring.py")


def main():
    if not os.path.isfile(CHECKER):
        print("  FAIL the gate cannot find %s — the checker it exists to run "
              "is gone, and a gate that cannot run its subject must not pass"
              % CHECKER)
        print("  1 guard(s), 1 red")
        return 1
    r = subprocess.run([sys.executable, CHECKER], cwd=REPO,
                       capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode == 0:
        # Its advisory NOTE lines (an exemption whose only reference is a tools/
        # script naming the path) are printed on a PASS too. Pass them through:
        # they are the checker's own report about the quality of the exemption
        # list, and swallowing them here is how that list rots.
        for ln in out.splitlines():
            if ln.strip():
                print("  note %s" % ln.rstrip())
        print("  ok   check_test_wiring: every test file is wired or explained")
        print("  1 guard(s), 0 red")
        return 0
    print("  FAIL check_test_wiring reports a test file that no rule runs. "
          "Writing a test and confirming it passes are both true, and neither "
          "makes it covered — test-core and test-nilpy ENUMERATE their tests, "
          "so a new file is gated only if the Makefile was edited too.")
    for ln in out.splitlines():
        print("       %s" % ln.rstrip())
    print("  1 guard(s), 1 red")
    return 1


if __name__ == "__main__":
    sys.exit(main())
