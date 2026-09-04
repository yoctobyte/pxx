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
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CHECKER = os.path.join(HERE, "check_test_wiring.py")
# an order of magnitude below the 2830 live subjects — see the note in main()
POPULATION_FLOOR = 250


def _since_control():
    """A/B the `--since` arm in a throwaway repo. -> None on pass, else why.

    A: a scaffold whose one test IS wired -> the checker must exit 0. This is
       the AIMED half: if the scaffold is wrong, B would "fail" for a reason
       that has nothing to do with the property, and the control would certify
       a broken instrument.
    B: add an UNTRACKED, unwired test -> the checker must exit nonzero and name
       it. That is the exact state a gate run sees under the prescribed
       workflow, and the state the arm used to be blind to.
    """
    import shutil
    import tempfile
    tmp = tempfile.mkdtemp(prefix="wiringgate-")
    try:
        os.makedirs(os.path.join(tmp, "tools"))
        os.makedirs(os.path.join(tmp, "test"))
        shutil.copy(CHECKER, os.path.join(tmp, "tools", "check_test_wiring.py"))
        with open(os.path.join(tmp, "test", "UNWIRED.txt"), "w") as f:
            f.write("# scaffold\n")
        with open(os.path.join(tmp, "test", "wired_one.pas"), "w") as f:
            f.write("program wired_one; begin end.\n")
        with open(os.path.join(tmp, "Makefile"), "w") as f:
            f.write("scaffold:\n\t./pascal26 test/wired_one.pas out\n")
        env = dict(os.environ, GIT_AUTHOR_NAME="g", GIT_AUTHOR_EMAIL="g@g",
                   GIT_COMMITTER_NAME="g", GIT_COMMITTER_EMAIL="g@g")
        for cmd in (["git", "init", "-q", "-b", "master"],
                    ["git", "add", "-A"],
                    ["git", "commit", "-q", "-m", "scaffold"]):
            g = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True,
                               env=env)
            if g.returncode != 0:
                return ("the --since control could not build its scaffold "
                        "(%s): %s" % (" ".join(cmd), (g.stderr or "").strip()))
        base = subprocess.run([sys.executable, "tools/check_test_wiring.py",
                               "--since", "HEAD~0"], cwd=tmp,
                              capture_output=True, text=True)
        if base.returncode != 0:
            return ("the --since control's BASELINE is not clean, so a failure "
                    "in the next step would prove nothing: %s"
                    % ((base.stdout or "") + (base.stderr or "")).strip())
        with open(os.path.join(tmp, "test", "orphan_probe.pas"), "w") as f:
            f.write("program orphan_probe; begin end.\n")
        got = subprocess.run([sys.executable, "tools/check_test_wiring.py",
                              "--since", "HEAD~0"], cwd=tmp,
                             capture_output=True, text=True)
        blob = (got.stdout or "") + (got.stderr or "")
        if got.returncode == 0 or "orphan_probe.pas" not in blob:
            return ("`--since` did not see an UNTRACKED unwired test. That is "
                    "the state every gate run sees, because CLAUDE.md gates "
                    "BEFORE the commit — so this arm would print PASS over "
                    "zero rows for everyone following it. rc=%d, output: %s"
                    % (got.returncode, blob.strip()))
        return None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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

    # DID IT LOOK AT ANYTHING? This gate's whole assertion is a NEGATIVE -- no
    # test file is unwired -- and a negative from a scan that found nothing to
    # scan is worth nothing. Measured 2026-08-30 by running this file against a
    # tree with an empty Makefile and an empty test/: it PASSED, green, in a
    # repo containing zero tests. So a glob that stopped matching, a renamed
    # test/, or a `git ls-files` that returns nothing in a fresh worktree would
    # all have read as coverage.
    #
    # THIS FLOOR IS A COLLAPSE DETECTOR, NOT A RATCHET, and the difference is
    # deliberate. A ratchet tracks the number closely and fires on drift; this
    # one is set an order of magnitude below the live population (2830 subjects
    # today) because the failure it exists for is the scan going to ~0, and a
    # tight bound here would fire on every ordinary week of test-writing. Do
    # NOT "tighten" it into a ratchet -- exit_observable_devtest.py already
    # owns the drift question for its own population, and the two are
    # different jobs.
    seen = re.search(r"scanned (\d+) test subject", out)
    if not seen or int(seen.group(1)) < POPULATION_FLOOR:
        print("  FAIL the checker did not report a plausible population — %s. "
              "A negative result from a scan that examined nothing is not "
              "coverage, and this gate asserts only a negative."
              % ("it printed no `scanned N` line at all" if not seen
                 else "it scanned %s subject(s), floor is %d"
                      % (seen.group(1), POPULATION_FLOOR)))
        for ln in out.splitlines():
            print("       %s" % ln.rstrip())
        print("  2 guard(s), 1 red")
        return 1

    # --- the PER-PUSH arm, which is a different question and was unfailable ---
    #
    # Everything above runs the CENSUS. `gate.sh quick` runs
    # `--since origin/$BRANCH`, and that arm answered over git-tracked files
    # only -- so a brand-new test file, which is UNTRACKED at the moment
    # CLAUDE.md tells you to gate (before committing, because the FPC seed
    # canary only runs while compiler/** is dirty), was outside the population.
    # It printed `PASS this push wires the tests it adds` over zero rows for
    # everybody following the prescribed order, and after the push the range
    # never contains the file again. Fixed 2026-09-04; this is the control that
    # proves the fix, because a bound nobody showed can fail is the failure
    # this whole file exists to name.
    #
    # RUN IN A THROWAWAY REPO, never against the live tree: a control that
    # writes into test/ to prove a point is a control that can leave the tree
    # red when it dies. mktemp gives a directory the OS reaps.
    since_rc = _since_control()
    if since_rc is not None:
        print("  FAIL %s" % since_rc)
        print("  3 guard(s), 1 red")
        return 1

    if r.returncode == 0:
        # Its advisory NOTE lines (an exemption whose only reference is a tools/
        # script naming the path) are printed on a PASS too. Pass them through:
        # they are the checker's own report about the quality of the exemption
        # list, and swallowing them here is how that list rots.
        for ln in out.splitlines():
            if ln.strip():
                print("  note %s" % ln.rstrip())
        print("  ok   the checker examined %s test subject(s) — the negative "
              "below is over a real population" % seen.group(1))
        print("  ok   check_test_wiring: every test file is wired or explained")
        print("  ok   --since sees an UNTRACKED new test — the per-push arm "
              "can fail at the moment the gate actually runs")
        print("  3 guard(s), 0 red")
        return 0
    print("  FAIL check_test_wiring reports a test file that no rule runs. "
          "Writing a test and confirming it passes are both true, and neither "
          "makes it covered — test-core and test-nilpy ENUMERATE their tests, "
          "so a new file is gated only if the Makefile was edited too.")
    for ln in out.splitlines():
        print("       %s" % ln.rstrip())
    print("  3 guard(s), 1 red")
    return 1


if __name__ == "__main__":
    sys.exit(main())
