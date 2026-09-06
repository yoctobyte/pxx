#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Guard: verify_pin must not file a verdict under a pin it did not measure.

Run: tools/twatch_pin_identity_devtest.py   (exit 0 = pass)

THE DEFECT THIS PINS
--------------------
`verify_pin` does `clone.checkout(<the pinned TREE>)`, and a pin commit is
always a DESCENDANT of the tree it pins -- you cut at tree T, then commit the
new binary as a child of T. So at T, `stable_linux_amd64/default/pinned` still
holds v(N-1), and every $(PXX_STABLE) job (lib-test, demos, test-fpjson) builds
with the PREVIOUS pin while the record says this one.

Three archived verdicts each judged the outgoing pin under the incoming pin's
name. The v398 one was annotated by hand as "a load-shaped flake, do NOT revert
on this count alone" -- the reds were not flakes, they were true statements
about a different binary, and a careful reader dismissed them because they did
not reproduce at HEAD, which is exactly what a previous-pin red does.

testmgr wrote the correct answer into report["pin"] the whole time and nothing
compared it. These rows assert the comparison exists and can fail.

WHY THE FOURTH CASE MATTERS MOST
--------------------------------
A tier with no pin-built job has no pin identity to check. The guard must NOT
refuse there -- that would disable the phase for the wrong reason -- but it must
SAY that the check could not run. An absent assertion that prints nothing is
indistinguishable from a passed one, which is how the previous three of these
shipped.
"""

import contextlib
import io
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch                                            # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILED = []


def check(name, cond, detail=""):
    print("  %-58s %s" % (name, "ok" if cond else "RED"))
    if not cond:
        FAILED.append("%s%s" % (name, (": " + detail) if detail else ""))


class FakeClone(object):
    path = REPO
    branch = "master"

    def checkout(self, sha):
        pass


class Stop(Exception):
    """Raised in place of the first post-assert call, so a run that gets past
    the identity check is distinguishable from one the check let through."""


def run_verify(pin_field, ver, tree):
    """Drive verify_pin far enough to exercise the identity check only."""
    clone = FakeClone()
    saved = (twatch.set_phase, twatch.clone_head_back, twatch.no_measurement,
             twatch.load_state, getattr(twatch, "run_gate", None))
    twatch.set_phase = lambda *a, **k: None
    twatch.clone_head_back = lambda c: None
    twatch.no_measurement = lambda r: False
    twatch.run_gate = lambda *a, **k: (
        {"verdict": "RED", "jobs": [{"name": "lib-test#1", "status": "fail"}],
         "pin": pin_field}, 0)

    def boom(*a, **k):
        raise Stop()
    twatch.load_state = boom
    buf = io.StringIO()
    got = None
    try:
        with contextlib.redirect_stdout(buf):
            got = twatch.verify_pin(clone, "seven", {}, ver, tree, "full")
    except Stop:
        got = "PAST"
    finally:
        (twatch.set_phase, twatch.clone_head_back, twatch.no_measurement,
         twatch.load_state, twatch.run_gate) = saved
    return got, buf.getvalue()


V407_TREE = "04559b9d6c5a9da084888f174e179b5ef5dc6894"

print("twatch pin-identity guard")

# --- the resolvers, against this ticket's own stated controls ---------------
tree401 = twatch.pinned_tree_for(FakeClone(), "v401")
check("pinned_tree_for(v401) is the TREE, not the pin commit",
      tree401 == "07d196aa45eae7ad3eab752396fb2d950fb3738f", str(tree401))
c401 = twatch.pin_commit_for(FakeClone(), "v401", tree401)
check("pin_commit_for(v401) is the pin COMMIT",
      (c401 or "").startswith("766b99f98"), str(c401))
gap = subprocess.run(["git", "rev-list", "--count", "07d196aa4..766b99f98"],
                     cwd=REPO, capture_output=True, text=True).stdout.strip()
check("the two are 4 commits apart (the ticket's control)", gap == "4", gap)

# THREE SPELLINGS OF ONE IDENTITY. pin.log writes v407, VERSION holds 407, and
# twatch's own `ver` carries the v. A helper that took one spelling returned
# None for the others -- and None here reads as "no such pin", not as a parse
# failure. Both spellings must give one answer.
check("pinned_tree_for accepts 'v407' and '407' alike",
      twatch.pinned_tree_for(FakeClone(), "v407")
      == twatch.pinned_tree_for(FakeClone(), "407") == V407_TREE)
check("pin_commit_for accepts 'v407' and '407' alike",
      twatch.pin_commit_for(FakeClone(), "v407", V407_TREE)
      == twatch.pin_commit_for(FakeClone(), "407", V407_TREE))
# An unknown pin must be None, NEVER a fallback to the tree: the entire point
# is that the commit and the tree are different objects.
check("an unknown version resolves to None, not to the tree",
      twatch.pinned_tree_for(FakeClone(), "v999") is None
      and twatch.pin_commit_for(FakeClone(), "v999", V407_TREE) is None)

# --- the guard itself -------------------------------------------------------
got, out = run_verify("v406 4bfd73d70588", "v407", V407_TREE)
check("MISMATCH refuses: publishes nothing", got is False, repr(got))
check("MISMATCH says both versions", "v406" in out and "v407" in out)
check("MISMATCH names the pin COMMIT and the distance",
      "51901941ef5d" in out and "17 commit(s)" in out)

got, out = run_verify("v407 095ef4811a5b", "v407", V407_TREE)
check("MATCH does not refuse", got == "PAST" and "REFUSED" not in out)

got, out = run_verify("407 095ef4811a5b", "v407", V407_TREE)
check("a spelling difference is not a mismatch",
      got == "PAST" and "REFUSED" not in out)

got, out = run_verify(None, "v407", V407_TREE)
check("no pin-built job: does NOT refuse", got == "PAST" and "REFUSED" not in out)
check("no pin-built job: SAYS the check could not run",
      "could not be checked" in out)

if FAILED:
    print("\n%d RED:" % len(FAILED))
    for f in FAILED:
        print("  - %s" % f)
    sys.exit(1)
print("pin-identity: all guards green")
