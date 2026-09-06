#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: Clone.publish() must COMMIT a deletion the caller made, not undo it.

WHY THIS EXISTS, and why devtest_stub_lifecycle.py could not catch it.
`close_stub_tickets` moves a healed stub from backlog/ to done/ with
`os.unlink(src)` plus a `publish([src, dst])`.  Its own comment says what must
not happen -- "staging only the destination leaves the stub in backlog on
origin and the ticket exists twice" -- and that is exactly what shipped in
50ca24994, which closed two regression cascades and deleted neither stub.  The
duplicates then sat on origin ranked at prio 70, and a seat claimed one of them
a day later and got a ticket that was already done.

The cause is not the staging.  It is that `publish()` ran
`git checkout <branch>` BEFORE `git add`, and the watcher is DETACHED at the
sha under test when it closes a stub -- so the branch checkout restored the
file the caller had just unlinked, after which `git add` saw it present and
staged nothing for it.

devtest_stub_lifecycle.py covers the same close path and passes, because its
FakeClone supplies a RECORDING publish: it mocks away the one method that had
the defect.  A test that stubs out the step under test cannot fail at it, which
is why this file uses a real repo, a real remote and the real Clone.publish.

Run: tools/twatch_publish_deletion_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

fails = []


def check(cond, what):
    print("  %-4s %s" % ("PASS" if cond else "FAIL", what))
    if not cond:
        fails.append(what)


def git(args, cwd):
    return subprocess.run(["git"] + args, cwd=cwd, capture_output=True,
                          text=True, check=True).stdout.strip()


def fixture(root):
    """A bare origin plus a watcher-shaped clone, with a stub already filed."""
    origin = os.path.join(root, "origin.git")
    git(["init", "-q", "--bare", "-b", "master", origin], root)
    work = os.path.join(root, "work")
    git(["clone", "-q", origin, work], root)
    git(["config", "user.email", "t@t"], work)
    git(["config", "user.name", "t"], work)
    for d in ("backlog", "done"):
        os.makedirs(os.path.join(work, "devdocs/progress", d), exist_ok=True)
    open(os.path.join(work, "devdocs/progress/backlog/stub.md"), "w").write("stub\n")
    open(os.path.join(work, "devdocs/progress/done/.keep"), "w").write("")
    git(["add", "-A"], work)
    git(["commit", "-qm", "file the stub"], work)
    # A second commit that EDITS the stub, and the edit is load-bearing.
    # `git checkout <branch>` only rewrites files whose content DIFFERS
    # between the detached sha and the branch tip -- so a stub nobody touched
    # is NOT restored and closes cleanly even under the old ordering. The
    # duplicate needs a stub that was edited after the sha under test, which
    # in the real case was an agent annotating it (cba854637, "CLEARED ...").
    # An annotated stub is exactly the one somebody cared about.
    # Without this commit the two checks below pass against the BROKEN
    # publish() too, and the test measures nothing.
    open(os.path.join(work, "devdocs/progress/backlog/stub.md"), "w").write(
        "stub\nannotated by an agent after the sha under test\n")
    git(["add", "-A"], work)
    git(["commit", "-qm", "an agent annotates the stub"], work)
    git(["push", "-q", "origin", "master"], work)
    return origin, work


def close_the_stub(work):
    """What close_stub_tickets does to the tree, minus the ticket bookkeeping."""
    assert os.path.exists(os.path.join(work, "devdocs/progress/backlog/stub.md")), \
        "aim the instrument: the stub must be present before the close unlinks it"
    os.unlink(os.path.join(work, "devdocs/progress/backlog/stub.md"))
    open(os.path.join(work, "devdocs/progress/done/stub.md"), "w").write("stub\nclosed\n")


REL = ["devdocs/progress/backlog/stub.md", "devdocs/progress/done/stub.md"]


def run_case(root, detached):
    origin, work = fixture(root)
    # Construct the Clone while the tree is CLEAN, as the daemon does at
    # startup -- its __init__ refuses a dirty checkout on purpose. The detach
    # and the unlink both happen afterwards, which is the real sequence.
    clone = tw.Clone(work, origin, "master")
    prev = git(["rev-parse", "HEAD~1"], work)
    if detached:
        git(["checkout", "-q", prev], work)
    close_the_stub(work)
    clone.publish("close the stub", paths=REL)
    on_origin = git(["ls-tree", "-r", "--name-only", "origin/master"], work).split("\n")
    return set(on_origin)


def main():
    print("twatch_publish_deletion_devtest: publish() must commit a deletion")

    # 1. The real condition: the watcher is DETACHED at the sha under test.
    with tempfile.TemporaryDirectory() as root:
        on_origin = run_case(root, detached=True)
    check("devdocs/progress/done/stub.md" in on_origin,
          "detached: the done/ copy reaches origin")
    check("devdocs/progress/backlog/stub.md" not in on_origin,
          "detached: the backlog/ copy is GONE from origin (the defect: it stayed)")
    check(not ("devdocs/progress/backlog/stub.md" in on_origin
               and "devdocs/progress/done/stub.md" in on_origin),
          "detached: the ticket does not exist in two buckets at once")

    # 2. On the branch already -- the case that always worked. Kept because a
    #    fix that only helps the detached path would otherwise look total.
    with tempfile.TemporaryDirectory() as root:
        on_origin = run_case(root, detached=False)
    check("devdocs/progress/backlog/stub.md" not in on_origin,
          "on-branch: the backlog/ copy is gone from origin too")

    # 3. POSITIVE CONTROL, drawn from the right population: reproduce the OLD
    #    ordering (checkout, then add, with no deletion replay) against the same
    #    fixture and assert it produces the duplicate. Without this row the two
    #    checks above pass for any publish() that happens not to restore the
    #    file -- including one that never deletes anything at all.
    with tempfile.TemporaryDirectory() as root:
        origin, work = fixture(root)
        prev = git(["rev-parse", "HEAD~1"], work)
        git(["checkout", "-q", prev], work)
        close_the_stub(work)
        git(["checkout", "-q", "master"], work)          # the old order
        git(["add", "--"] + REL, work)
        git(["commit", "-qm", "old ordering"] + ["--"] + REL, work)
        git(["push", "-q", "origin", "master"], work)
        old = set(git(["ls-tree", "-r", "--name-only", "origin/master"], work).split("\n"))
    check("devdocs/progress/backlog/stub.md" in old,
          "CONTROL: the pre-fix ordering DOES leave the stub in backlog/ "
          "(if this passes, the test above is not measuring the fix)")

    print("%s (%d check(s), %d failure(s))"
          % ("PASS" if not fails else "FAIL", 5, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
