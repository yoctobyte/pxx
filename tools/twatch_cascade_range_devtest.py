#!/usr/bin/env python3
"""A cascade ticket must name its RANGE, and must never let a docs-only sha
stand as the accusation.

Reproduces the 2026-08-19 incident directly: regression-cascade-4e27dc2be114
named a commit that touched three files, all under devdocs/progress/, while the
real cause sat six commits back inside the same recorded 17-commit range. The
watcher HAD the range in its ledger; only the ticket dropped it, so every reader
saw one sha presented as the culprit.

Run: python3 tools/twatch_cascade_range_devtest.py
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch


def git(repo, *a):
    return subprocess.run(["git", "-C", repo] + list(a), check=True,
                          capture_output=True, text=True).stdout.strip()


def commit(repo, path, text, msg):
    full = os.path.join(repo, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", msg)
    return git(repo, "rev-parse", "HEAD")


class FakeClone:
    def __init__(self, path):
        self.path = path
        # the watched branch: verdict-deriving helpers ask the CLONE,
        # never a process default, so a double needs one too
        self.branch = "master"


def main():
    fails = []

    def check(cond, what):
        print(("  ok   " if cond else "  FAIL ") + what)
        if not cond:
            fails.append(what)

    with tempfile.TemporaryDirectory() as tmp:
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        git(repo, "init", "-q")
        git(repo, "config", "user.email", "t@example.com")
        git(repo, "config", "user.name", "t")

        good = commit(repo, "compiler/base.inc", "0\n", "seed")
        # the real cause, buried mid-range
        cause = commit(repo, "compiler/pyparser.inc", "import rule\n",
                       "feat(A,N): a bare NilPy import resolves to Python")
        mid = commit(repo, "docs/guide.md", "prose\n", "docs: guide")
        # ...and the tested sha on top: docs only, cannot have caused anything
        bad = commit(repo, "devdocs/progress/BOARD.md", "board\n",
                     "triage(A/P): re-type Initialize/Finalize as a bug")

        rng = [cause, mid, bad]
        clone = FakeClone(repo)
        reg = {"job": "cascade@" + bad[:12], "bad": bad, "good": good,
               "range": rng, "cascade": ["test-core#src:a.npy"]}

        print("cascade_range_note — docs-only tested sha")
        note = twatch.cascade_range_note(clone, reg)
        check("CANNOT be the cause" in note,
              "says the docs-only sha cannot be the cause")
        check(bad[:12] in note, "still names the tested sha")
        check(good[:12] in note, "names the last good sha")
        check("3 commit(s) in range" in note, "states the range size")
        check(cause[:12] in note, "lists the buildable commit that IS the cause")
        check(mid[:12] not in note,
              "omits the docs-only commit from the suspect list")
        check("No idle bisect will happen" in note,
              "does not promise a bisect that bisect_step skips for cascades")

        print("cascade_range_note — buildable tested sha")
        bad2 = commit(repo, "compiler/x.inc", "1\n", "fix(A): something real")
        reg2 = dict(reg, bad=bad2, range=rng + [bad2])
        note2 = twatch.cascade_range_note(clone, reg2)
        check("CANNOT be the cause" not in note2,
              "no exoneration banner when the tested sha is buildable")
        check(bad2[:12] in note2, "lists the tested sha as a suspect")

        print("cascade_range_note — no range")
        note3 = twatch.cascade_range_note(clone, dict(reg, range=[]))
        check("range **unknown**" in note3, "says the range is unknown")
        check("Hand-triage" in note3, "sends an unbounded cascade to a human")

        print("cascade_range_note — range with nothing buildable")
        docsonly = commit(repo, "docs/b.md", "b\n", "docs: b")
        note4 = twatch.cascade_range_note(
            clone, dict(reg, bad=docsonly, range=[mid, docsonly]))
        check("points at flakiness" in note4,
              "an all-docs range points away from the commits, not at one")

        print("suspect cap is announced, never silent")
        many = [commit(repo, "compiler/f%d.inc" % i, "%d\n" % i, "fix %d" % i)
                for i in range(twatch.CASCADE_SUSPECTS + 4)]
        note5 = twatch.cascade_range_note(
            clone, dict(reg, bad=many[-1], range=many))
        check("and 4 earlier commit(s) in the range, not listed" in note5,
              "names how many suspects were dropped by the cap")
        check(note5.count("\n- `") == twatch.CASCADE_SUSPECTS,
              "lists exactly CASCADE_SUSPECTS entries")

    print()
    if fails:
        print("FAILED %d check(s)" % len(fails))
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
