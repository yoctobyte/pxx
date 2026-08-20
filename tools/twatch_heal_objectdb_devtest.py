#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: an unclean shutdown must not take the watcher down permanently.

heal_truncations() already restores tracked WORKTREE files that a power cut
brought back at length zero (2026-08-11, plexus). On 2026-08-20 the same kind
of event — borg's PSU failed and took the whole house down — zeroed something
one level below it: the loose object holding the clone's own HEAD commit. Every
git command then failed with

    error: object file .git/objects/80/4829ad… is empty
    fatal: bad object HEAD

and that includes the `git status` heal_truncations() opens with. The healer
raised RuntimeError from its first line, Clone.__init__ died with it, and the
daemon exited 1 in 315ms — eleven times, until StartLimitBurst gave up into
`failed`. Nothing tested a commit for 4h40m, and the repo had in fact become
readable again ~17 minutes in, when an unrelated fetch packed a good copy of
the object. The corruption outlived itself; the give-up did not.

So the guard has to sit below the one it protects. Invariants:

  * a zero-length loose object is deleted and the repo comes back — whether the
    good copy is in a pack, on the remote, or nowhere but origin;
  * an object that is GONE, not merely empty, is refetched (the sweep finds
    nothing to delete, so the fallback has to carry it);
  * a zero-length `.git/index` is rebuilt from HEAD — removing it is not
    enough, because an ABSENT index reads as "nothing is tracked" and every
    file in HEAD then shows up staged-deleted, which the dirty guard refuses as
    a dev checkout with 40k deletions in it;
  * the two healers COMPOSE: the real incident zeroed the object database and
    15 worktree files, and the clone has to end clean, not merely readable;
  * a healthy clone is not touched, and a dirty one is still refused with the
    human's edit intact. The recovery is a `reset --hard`; it must never be
    reachable from a state where a human could lose work to it.

Run: tools/twatch_heal_objectdb_devtest.py   (exit 0 = pass)
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

FILES = ("compiler/thing.pas", tw.TSTATE_REL + "/plexus.json")


def git(*a, cwd):
    return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True,
                          text=True)


def build(root):
    """A watcher clone with a real origin. Returns (origin, clone).

    --no-hardlinks matters: a local clone hardlinks its objects by default, so
    truncating one here would truncate origin's copy through the same inode and
    the test would be measuring a repo with no good copy anywhere.
    """
    origin = os.path.join(root, "origin.git")
    seed = os.path.join(root, "seed")
    clone = os.path.join(root, "clone")
    git("init", "-q", "--bare", "-b", "master", origin, cwd=root)
    git("clone", "-q", origin, seed, cwd=root)
    git("config", "user.email", "devtest@local", cwd=seed)
    git("config", "user.name", "devtest", cwd=seed)
    for rel in FILES:
        os.makedirs(os.path.join(seed, os.path.dirname(rel)), exist_ok=True)
        write(seed, rel, "the platonic content of %s\n" % rel)
    git("add", "-A", cwd=seed)
    git("commit", "-qm", "base", cwd=seed)
    git("push", "-q", "origin", "HEAD:master", cwd=seed)
    git("clone", "-q", "--no-hardlinks", origin, clone, cwd=root)
    return origin, clone


def write(root, rel, text):
    with open(os.path.join(root, rel), "w") as f:
        f.write(text)


def head(clone):
    return git("rev-parse", "HEAD", cwd=clone).stdout.strip()


def loose(clone, sha):
    return os.path.join(clone, ".git", "objects", sha[:2], sha[2:])


def readable(clone):
    return git("status", "--porcelain", "-uno", cwd=clone).returncode == 0


def dirt(clone):
    return git("status", "--porcelain", "-uno", cwd=clone).stdout.strip()


def t_zeroed_head_object(root):
    """The 2026-08-20 signature: HEAD's loose object came back at length 0."""
    origin, clone = build(root)
    sha = head(clone)
    open(loose(clone, sha), "w").close()
    assert not readable(clone), "setup failed — git still reads the clone"
    tw.Clone(clone, origin, "master")
    assert readable(clone), "still unreadable after healing"
    assert head(clone) == sha, "HEAD moved: %s != %s" % (head(clone), sha)
    return "empty object swept, clone readable, HEAD unmoved"


def t_missing_head_object(root):
    """Gone, not empty: the sweep has nothing to delete, so refetch carries it."""
    origin, clone = build(root)
    sha = head(clone)
    os.remove(loose(clone, sha))
    assert not readable(clone), "setup failed"
    tw.Clone(clone, origin, "master")
    assert readable(clone), "still unreadable after healing"
    assert head(clone) == sha, "HEAD moved: %s != %s" % (head(clone), sha)
    return "refetched from origin, HEAD unmoved"


def t_zeroed_index(root):
    """A zero-byte index must be REBUILT, not merely removed."""
    origin, clone = build(root)
    open(os.path.join(clone, ".git", "index"), "w").close()
    assert not readable(clone), "setup failed"
    tw.Clone(clone, origin, "master")
    assert readable(clone), "still unreadable after healing"
    assert dirt(clone) == "", ("index not rebuilt — tree reads dirty: %r"
                               % dirt(clone)[:200])
    return "index rebuilt from HEAD, tree clean"


def t_object_and_worktree(root):
    """The whole incident: object database AND worktree zeroed together."""
    origin, clone = build(root)
    sha = head(clone)
    open(loose(clone, sha), "w").close()
    for rel in FILES:
        open(os.path.join(clone, rel), "w").close()
    c = tw.Clone(clone, origin, "master")
    assert readable(clone), "still unreadable after healing"
    assert dirt(clone) == "", "clone still dirty: %r" % dirt(clone)[:200]
    for rel in FILES:
        assert os.path.getsize(os.path.join(clone, rel)) > 0, \
            "%s still zero-length" % rel
    assert c.dirty() == "", "Clone.dirty() disagrees with git"
    return "both healers composed; tree clean and files restored"


def t_healthy_untouched(root):
    """A healthy clone is not repaired, reset, or otherwise molested."""
    origin, clone = build(root)
    sha = head(clone)
    c = tw.Clone(clone, origin, "master")
    assert c.heal_object_db() == [], "healed a healthy clone"
    assert head(clone) == sha, "HEAD moved on a healthy clone"
    return "no-op, as it must be on every ordinary start"


def t_dirty_still_refused(root):
    """The recovery is a reset --hard: keep it unreachable from a dev tree."""
    origin, clone = build(root)
    edit = "a human is editing this, mid-run\n"
    write(clone, FILES[0], edit)
    try:
        tw.Clone(clone, origin, "master")
    except SystemExit:
        got = open(os.path.join(clone, FILES[0])).read()
        assert got == edit, "the human's edit was destroyed: %r" % got
        return "refused, edit intact"
    raise AssertionError("accepted a dirty checkout")


def main():
    rc = 0
    tests = (t_zeroed_head_object, t_missing_head_object, t_zeroed_index,
             t_object_and_worktree, t_healthy_untouched, t_dirty_still_refused)
    for fn in tests:
        root = tempfile.mkdtemp(prefix="devtest-healobj-")
        try:
            note = fn(root)
            print("  ok   %s — %s" % (fn.__name__, note))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
        finally:
            shutil.rmtree(root, ignore_errors=True)
    print("object-db healing OK" if rc == 0 else "object-db healing BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
