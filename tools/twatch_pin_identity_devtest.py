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
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch                                            # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILED = []


def check(name, cond, detail=""):
    print("  %-58s %s" % (name, "ok" if cond else "RED"))
    if not cond:
        FAILED.append("%s%s" % (name, (": " + detail) if detail else ""))


class ReadOnlyClone(object):
    """Points at the real repo, and is used ONLY for read-only resolver queries.

    It must never reach the artefact-restore path: that runs `git checkout
    <commit> -- stable_linux_amd64` in `clone.path`, and an earlier draft of
    this file handed it REPO and mutated the actual working tree. It restored
    cleanly, which is the bad luck -- a devtest that only sometimes leaves your
    checkout dirty is worse than one that always does.
    """
    path = REPO
    branch = "master"

    def checkout(self, sha):
        pass


def git(args, cwd):
    return subprocess.run(["git"] + args, cwd=cwd, capture_output=True,
                          text=True)


def build_fixture(tmp):
    """A repo shaped like a real pin: tree T, then the pin commit as its CHILD.

    That parent/child order IS the defect -- at T, stable_linux_amd64 still
    holds the previous pin, because the binary is committed afterwards.
    """
    git(["init", "-q", "-b", "master", tmp], os.path.dirname(tmp) or ".")
    git(["config", "user.email", "d@e"], tmp)
    git(["config", "user.name", "devtest"], tmp)
    d = os.path.join(tmp, "stable_linux_amd64", "default")
    os.makedirs(d)

    def w(name, text):
        with open(os.path.join(d, name), "w") as f:
            f.write(text)

    w("VERSION", "406\n")
    w("pinned", "BINARY-v406\n")
    w("pin.log", "2026-09-01T00:00:00Z  pinned v406  aa  (was zz)  " + "0" * 40
      + "\n")
    git(["add", "-A"], tmp); git(["commit", "-qm", "base"], tmp)

    with open(os.path.join(tmp, "src.txt"), "w") as f:
        f.write("the tree the pin is cut from\n")
    git(["add", "-A"], tmp); git(["commit", "-qm", "tree T"], tmp)
    tree = git(["rev-parse", "HEAD"], tmp).stdout.strip()

    # ...and now the pin commit, as T's CHILD, carrying the new artefacts.
    w("VERSION", "407\n")
    w("pinned", "BINARY-v407\n")
    with open(os.path.join(d, "pin.log"), "a") as f:
        f.write("2026-09-02T00:00:00Z  pinned v407  bb  (was aa)  %s\n" % tree)
    git(["add", "-A"], tmp); git(["commit", "-qm", "chore(stable): pin v407"], tmp)
    commit = git(["rev-parse", "HEAD"], tmp).stdout.strip()

    # A NEWER PIN ON THE BRANCH TIP, and it is not decoration -- it is the only
    # condition under which the wedge occurs at all. Measured while writing
    # this: with master's artefacts IDENTICAL to the restored ones, `git
    # checkout master` succeeds happily, because git refuses only when the
    # target content DIFFERS from the local change. So verifying the current pin
    # usually does not wedge, and verifying one that a newer pin has overtaken
    # does. That second case is real (pin_changed_mid_run is a tracked
    # condition) and it is the one the cleanup is for.
    w("VERSION", "408\n")
    w("pinned", "BINARY-v408\n")
    with open(os.path.join(d, "pin.log"), "a") as f:
        f.write("2026-09-03T00:00:00Z  pinned v408  cc  (was bb)  %s\n" % commit)
    git(["add", "-A"], tmp); git(["commit", "-qm", "chore(stable): pin v408"], tmp)
    git(["update-ref", "refs/remotes/origin/master",
         git(["rev-parse", "HEAD"], tmp).stdout.strip()], tmp)

    class FixtureClone(object):
        path = tmp
        branch = "master"

        def checkout(self, sha):
            git(["checkout", "-q", "--detach", sha], tmp)

    return FixtureClone(), tree, commit


def version_on_disk(tmp):
    with open(os.path.join(tmp, "stable_linux_amd64/default/VERSION")) as f:
        return f.read().strip()


class Stop(Exception):
    """Raised in place of the first post-assert call, so a run that gets past
    the identity check is distinguishable from one the check let through."""


def run_verify(pin_field, ver, tree, clone=None):
    """Drive verify_pin far enough to exercise the identity check only."""
    clone = clone or ReadOnlyClone()
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
tree401 = twatch.pinned_tree_for(ReadOnlyClone(), "v401")
check("pinned_tree_for(v401) is the TREE, not the pin commit",
      tree401 == "07d196aa45eae7ad3eab752396fb2d950fb3738f", str(tree401))
c401 = twatch.pin_commit_for(ReadOnlyClone(), "v401", tree401)
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
      twatch.pinned_tree_for(ReadOnlyClone(), "v407")
      == twatch.pinned_tree_for(ReadOnlyClone(), "407") == V407_TREE)
check("pin_commit_for accepts 'v407' and '407' alike",
      twatch.pin_commit_for(ReadOnlyClone(), "v407", V407_TREE)
      == twatch.pin_commit_for(ReadOnlyClone(), "407", V407_TREE))
# An unknown pin must be None, NEVER a fallback to the tree: the entire point
# is that the commit and the tree are different objects.
check("an unknown version resolves to None, not to the tree",
      twatch.pinned_tree_for(ReadOnlyClone(), "v999") is None
      and twatch.pin_commit_for(ReadOnlyClone(), "v999", V407_TREE) is None)

# --- the artefact restore, on a real fixture repo --------------------------
TMP = tempfile.mkdtemp(prefix="pin-identity-fixture.")
try:
    fx, f_tree, f_commit = build_fixture(os.path.join(TMP, "clone"))

    check("fixture: pinned_tree_for finds the TREE",
          twatch.pinned_tree_for(fx, "v407") == f_tree)
    check("fixture: pin_commit_for finds its CHILD, the pin commit",
          twatch.pin_commit_for(fx, "v407", f_tree) == f_commit)

    # THE DEFECT ITSELF, reproduced: check out the pinned tree and the artefacts
    # are the PREVIOUS pin's. If this row ever goes green-by-passing, the whole
    # ticket has evaporated and the fix below is measuring nothing.
    fx.checkout(f_tree)
    check("DEFECT REPRODUCED: at the pinned tree, VERSION is the PREVIOUS pin",
          version_on_disk(fx.path) == "406", version_on_disk(fx.path))

    # ...and the fix.
    git(["checkout", f_commit, "--", twatch.PIN_ARTEFACT_REL], fx.path)
    check("restore from the pin commit makes it the pin under test",
          version_on_disk(fx.path) == "407", version_on_disk(fx.path))

    # THE WEDGE CONTROL, and it is the reason the cleanup exists at all.
    # clone_head_back is a plain `git checkout <branch>`; with our restore still
    # in the worktree it must FAIL. A cleanup nobody proved was load-bearing is
    # a line the next reader deletes.
    wedged = git(["checkout", "-q", fx.branch], fx.path)
    check("WITHOUT the cleanup, checking the branch back out FAILS (the wedge)",
          wedged.returncode != 0, "rc=%d" % wedged.returncode)
    check("...and the wedge left HEAD where it was, still detached at the tree",
          git(["rev-parse", "HEAD"], fx.path).stdout.strip() == f_tree)

    # `HEAD --`, not bare `--`: the restore wrote the INDEX too, and bare `--`
    # restores FROM the index, which would keep exactly what we are removing.
    git(["checkout", "HEAD", "--", twatch.PIN_ARTEFACT_REL], fx.path)
    check("after `git checkout HEAD -- <artefacts>`, the tree is ours again",
          version_on_disk(fx.path) == "406", version_on_disk(fx.path))
    back = git(["checkout", "-q", fx.branch], fx.path)
    check("...and clone_head_back's plain checkout now SUCCEEDS",
          back.returncode == 0, back.stderr.strip()[:120])
    check("no dirt is left behind",
          git(["status", "--porcelain"], fx.path).stdout.strip() == "")

    # --- the identity check, driven on the fixture (never the real repo) -----
    got, out = run_verify("v406 4bfd73d70588", "v407", f_tree, clone=fx)
    check("MISMATCH refuses: publishes nothing", got is False, repr(got))
    check("MISMATCH says both versions", "v406" in out and "v407" in out)
    check("MISMATCH names the pin COMMIT", f_commit[:12] in out)

    got, out = run_verify("v407 095ef4811a5b", "v407", f_tree, clone=fx)
    check("MATCH does not refuse", got == "PAST" and "REFUSED" not in out)

    got, out = run_verify("407 095ef4811a5b", "v407", f_tree, clone=fx)
    check("a spelling difference is not a mismatch",
          got == "PAST" and "REFUSED" not in out)

    got, out = run_verify(None, "v407", f_tree, clone=fx)
    check("no pin-built job: does NOT refuse",
          got == "PAST" and "REFUSED" not in out)
    check("no pin-built job: SAYS the check could not run",
          "could not be checked" in out)

    check("verify_pin left the fixture clean",
          git(["status", "--porcelain"], fx.path).stdout.strip() == "",
          git(["status", "--porcelain"], fx.path).stdout.strip()[:120])
finally:
    shutil.rmtree(TMP, ignore_errors=True)

# The real checkout must be untouched: an earlier draft drove verify_pin with a
# clone pointing at REPO, so the restore ran against the actual working tree.
check("the real checkout's pinned artefacts are untouched",
      subprocess.run(["git", "diff", "--quiet", "HEAD", "--",
                      "stable_linux_amd64"], cwd=REPO).returncode == 0)

if FAILED:
    print("\n%d RED:" % len(FAILED))
    for f in FAILED:
        print("  - %s" % f)
    sys.exit(1)
print("pin-identity: all guards green")
