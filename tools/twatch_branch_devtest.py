#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the watcher must ask the branch the sha is actually ON.

Until 2026-08-25 every "origin/…" in twatch was the literal `master`, which was
true because master was where work happened. That day the user moved daily work
to `dev` and made master a snapshot advanced once or twice a day. Two things
break at that moment, and only one of them is loud:

  * LOUD — a daemon still watching master re-confirms a tree that has stopped
    moving while every real fix lands unwatched. Someone notices within a day.
  * SILENT, and much worse — the revert-detection helpers ask master whether
    anything in a sha's range was reverted. A commit on dev is not on master,
    so `git log <sha>..origin/master` is not "nothing was reverted", it is a
    different question entirely. The answers land in tickets as
    "LIKELY ALREADY FIXED — verify before acting", which is a confident claim
    about a revert that may not exist, attached to a real red.

So: the branch is config (`trackt config branch dev`), readers default to the
branch they are standing on, and anything deriving a VERDICT asks the clone's
own branch rather than a process-wide default.

Scratch git repos only. Run: tools/twatch_branch_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE,
                                                                "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)


def git(cwd, *a, check=True):
    r = subprocess.run(["git", "-c", "user.name=devtest", "-c",
                        "user.email=d@e", "-c", "commit.gpgsign=false", *a],
                       cwd=cwd, capture_output=True, text=True)
    if check and r.returncode:
        raise RuntimeError("git %s: %s" % (" ".join(a), r.stderr.strip()))
    return r.stdout.strip()


def commit(repo, name, text, subject):
    with open(os.path.join(repo, name), "w") as f:
        f.write(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", subject)
    return git(repo, "rev-parse", "HEAD")


def build(root):
    """origin with master and dev; dev carries a commit AND its revert.

    master deliberately does NOT carry either — that asymmetry is the whole
    point: asking master about a dev sha gives a wrong answer, not an error.
    """
    origin = os.path.join(root, "origin.git")
    seed = os.path.join(root, "seed")
    git(root, "init", "-q", "--bare", "-b", "master", origin)
    git(root, "clone", "-q", origin, seed)
    commit(seed, "a.txt", "base\n", "base")
    git(seed, "push", "-q", "origin", "HEAD:master")
    git(seed, "checkout", "-q", "-b", "dev")
    bad = commit(seed, "b.txt", "boom\n", "the change that broke it")
    git(seed, "revert", "--no-edit", bad)
    git(seed, "push", "-q", "origin", "dev")
    return origin, bad


def clone_on(root, origin, branch, name):
    path = os.path.join(root, name)
    git(root, "clone", "-q", "--no-hardlinks", "-b", branch, origin, path)
    return tw.Clone(path, origin, branch)


def t_repo_branch_reads_the_checkout():
    root = tempfile.mkdtemp(prefix="devtest-branch-")
    try:
        origin, _ = build(root)
        c = clone_on(root, origin, "dev", "c1")
        assert tw.repo_branch(c.path) == "dev", tw.repo_branch(c.path)
        git(c.path, "checkout", "-q", "--detach", "HEAD")
        assert tw.repo_branch(c.path) == "master", \
            "a detached checkout must fall back, not return an empty ref"
        return "branch read from the checkout, detached falls back to master"
    finally:
        shutil.rmtree(root, ignore_errors=True)


def t_origin_ref_prefers_the_clone():
    root = tempfile.mkdtemp(prefix="devtest-branch-")
    try:
        origin, _ = build(root)
        c = clone_on(root, origin, "dev", "c1")
        prev = tw.BRANCH
        try:
            tw.BRANCH = "master"
            assert tw.origin_ref(c) == "origin/dev", tw.origin_ref(c)
            assert tw.origin_ref() == "origin/master", tw.origin_ref()
        finally:
            tw.BRANCH = prev
        return "clone wins where a verdict is derived; global is the fallback"
    finally:
        shutil.rmtree(root, ignore_errors=True)


def t_revert_detection_asks_the_right_branch():
    """THE bug: a revert that exists on dev, asked about from master."""
    root = tempfile.mkdtemp(prefix="devtest-branch-")
    try:
        origin, bad = build(root)
        dev = clone_on(root, origin, "dev", "cdev")
        got = tw.revert_of_range(dev, bad, bad + "^")
        assert got, "the revert IS on dev and was not found"
        assert got[0] != bad and "broke it" in got[1], got

        # Same sha, asked from a master clone. master has neither the commit
        # nor its revert, so the honest answer is "no revert here" — never a
        # claim about a range this branch does not contain.
        mst = clone_on(root, origin, "master", "cmst")
        git(mst.path, "fetch", "-q", "origin", "dev")     # sha is reachable
        assert tw.revert_of_range(mst, bad, bad + "^") is None, \
            "claimed a revert on a branch that carries neither commit"
        return "found on dev, not claimed on master"
    finally:
        shutil.rmtree(root, ignore_errors=True)


def t_conf_carries_the_branch():
    assert tw.CONF_DEFAULTS.get("branch") == "master", \
        "default branch must stay master: an unconfigured watcher elsewhere " \
        "must not silently follow this repo's dev"
    return "twatch.conf `branch` exists and defaults to master"


def main():
    rc = 0
    for fn in (t_repo_branch_reads_the_checkout, t_origin_ref_prefers_the_clone,
               t_revert_detection_asks_the_right_branch, t_conf_carries_the_branch):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("branch targeting OK" if rc == 0 else "branch targeting BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
