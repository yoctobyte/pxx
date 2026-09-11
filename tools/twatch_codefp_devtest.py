#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the code-staleness check reads the DEPLOYED twatch.py, not the worktree.

bug-t-trackt-status-compares-the-daemon-against-the-sha-under-tests-twatchpy.

`trackt status` warns when the running daemon predates a landed twatch fix. It
compared the daemon's `code_fp` against `code_fingerprint(clone/tools/twatch.py)`
-- the file ON DISK -- and for most of every cycle that file is the version at
the SHA UNDER TEST, because a watcher clone is detached there while it gates.

Measured on borg 2026-09-11: `STALE -- running 1d5c476a6328 while the clone has
17bbd9d15049`. 1d5c476a6328 WAS origin/master; 17bbd9d15049 was the twatch.py of
`51901941ef5d`, the pin under verification. The restart it asked for aborted a
running fuzz slice to replace the code with itself.

The two rows below are the two directions, and the second is the one that costs
something real:

1. **A current daemon must not read as stale.** The false alarm above. Cheap
   individually, expensive as a habit -- a warning that cries wolf during every
   gate is one nobody reads during the cycle it is right.

2. **A stale daemon must not read as current.** Land a twatch fix while a gate
   runs on an older sha and the old comparison is against THAT sha's file, which
   the daemon may well match. The check then goes quiet at exactly the moment it
   exists for, which is the `NEAR BUDGET` shape from devdocs/dev/track-t.md: an
   instrument that reports only in the state where it is not yet needed.

Built on a synthetic two-commit repo rather than a clone of this one: the guard
is about which REF is read, so the fixture needs exactly two versions of one
file and nothing else. A fixture that takes a minute to build is a fixture
somebody eventually skips.

Run: python3 tools/twatch_codefp_devtest.py
"""

import hashlib
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import twatch                                                   # noqa: E402

fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                  # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-56s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def git(repo, *args):
    return subprocess.run(("git", "-C", str(repo)) + args,
                          capture_output=True, text=True, check=True).stdout


def fp(text):
    return hashlib.sha256(text.encode()).hexdigest()[:12]


def fixture(tmp):
    """origin + a clone whose master carries v2 and whose history carries v1."""
    origin = pathlib.Path(tmp) / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "master", str(origin)],
                   check=True)
    seed = pathlib.Path(tmp) / "seed"
    subprocess.run(["git", "clone", "-q", str(origin), str(seed)],
                   check=True, capture_output=True)
    git(seed, "config", "user.email", "devtest@example.invalid")
    git(seed, "config", "user.name", "devtest")
    (seed / "tools").mkdir()
    old_sha = None
    for body in ("v1", "v2"):
        (seed / "tools" / "twatch.py").write_text(body)
        git(seed, "add", "tools/twatch.py")
        git(seed, "commit", "-q", "-m", body)
        if body == "v1":
            old_sha = git(seed, "rev-parse", "HEAD").strip()
    git(seed, "push", "-q", "origin", "master")
    clone = pathlib.Path(tmp) / "clone"
    subprocess.run(["git", "clone", "-q", str(origin), str(clone)], check=True)
    return clone, old_sha


def main():
    with tempfile.TemporaryDirectory() as tmp:
        clone, old_sha = fixture(tmp)

        print("1. on a branch, the worktree file IS what a restart loads")
        check(not twatch.head_detached(clone), "the fixture clone is on master")
        check(twatch.deployed_code_fingerprint(clone) == fp("v2"),
              "deployed fingerprint is master's twatch.py",
              "got %s, want %s" % (twatch.deployed_code_fingerprint(clone),
                                   fp("v2")))

        print("\n2. detached at an older sha — the watcher's normal state")
        git(clone, "checkout", "-q", "--detach", old_sha)
        worktree = twatch.code_fingerprint(str(clone / "tools" / "twatch.py"))
        deployed = twatch.deployed_code_fingerprint(clone)
        check(twatch.head_detached(clone), "the fixture clone is detached")
        # The control: this row is what the pre-fix reader compared against, and
        # it is stated as an assertion so the fixture cannot go quietly inert. A
        # fixture whose two versions became identical would pass every row below
        # while testing nothing.
        check(worktree == fp("v1") and worktree != fp("v2"),
              "the worktree file is the OLD version (fixture is live)",
              "worktree=%s v1=%s v2=%s" % (worktree, fp("v1"), fp("v2")))
        check(deployed == fp("v2"),
              "deployed fingerprint still names master, not the sha under test",
              "got %s, want %s" % (deployed, fp("v2")))
        # Direction 2, spelled out rather than left implicit in the row above:
        # a daemon holding v1 while master carries v2 IS stale, and the pre-fix
        # comparison (v1 vs the detached worktree's v1) called it current.
        check(fp("v1") != deployed,
              "so a daemon still holding v1 is reported STALE while detached",
              "pre-fix this compared v1 against v1 and said nothing")

        print("\n  %d guard(s), %d FAIL" % (6, len(fails)))
        return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
