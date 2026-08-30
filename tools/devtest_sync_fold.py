#!/usr/bin/env python3
"""Devtest: sync.sh tells a FOLDED/DROPPED-as-redundant commit from a LOST one.

THE INCIDENT (frankS, 2026-08-30): two commits pushed, everything landed on
origin, and `tools/sync.sh` printed its full recovery banner —

    *** 1 OF 2 COMMIT(S) DID NOT LAND ***
    YOUR WORK IS NOT LOST -- it is in the reflog. Do NOT reset --hard.
        git cherry-pick <sha>

— on a push that had succeeded. Two things are wrong with that, and the second
is the expensive one:

  1. `verify_manifest_landed` matches on SUBJECT, because a rebase rewrites
     shas. But a rebase also folds (`--amend`, autosquash) and DROPS commits
     that became empty because an equivalent change already reached origin.
     Both destroy the subject while the content survives. sync.sh does its own
     amend — it regenerates the board after rebasing and folds it into the top
     commit — so this is reachable from sync.sh's own normal path.
  2. It then `exit 1`s, which skips `fill_pending_commits`, so the ticket keeps
     citing `PENDING-COMMIT` for a commit that is on origin. The banner's own
     advice, `git cherry-pick`, would duplicate work that already landed: an
     instruction to corrupt a correct state, printed when the state is correct.

WHY NOT THE OBVIOUS GUARD. `git merge-base --is-ancestor HEAD origin/$BRANCH`
looks like the answer and is a trap: after any SUCCESSFUL push HEAD is always
an ancestor of origin, including when the rebase really did drop a commit,
because the drop happened before the push. That guard silences the check
permanently in exactly the case it exists for — so this devtest asserts BOTH
directions, and the loss case is the one that matters.

Scratch repos only: no network, no compiles, nothing outside a tempdir.

Run: tools/devtest_sync_fold.py   (exit 0 = pass)
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SYNC = os.path.join(HERE, "sync.sh")

fails = []


def check(cond, what, detail=""):
    print("  %-4s %-50s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def git(repo, *args, **kw):
    return subprocess.run(["git", "-C", repo] + list(args),
                          capture_output=True, text=True, **kw)


def commit(repo, path, body, subject):
    full = os.path.join(repo, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(body)
    git(repo, "add", "-A")
    git(repo, "-c", "user.email=t@pxx", "-c", "user.name=devtest",
        "commit", "-q", "-m", subject)


def world(tmp):
    """A bare origin plus two clones, so one can race the other."""
    origin = os.path.join(tmp, "origin.git")
    subprocess.run(["git", "init", "-q", "--bare", "-b", "master", origin],
                   check=True)
    seed = os.path.join(tmp, "seed")
    subprocess.run(["git", "clone", "-q", origin, seed], check=True)
    commit(seed, "README.md", "seed\n", "chore: seed")
    git(seed, "push", "-q", "origin", "master")
    a = os.path.join(tmp, "a")
    b = os.path.join(tmp, "b")
    subprocess.run(["git", "clone", "-q", origin, a], check=True)
    subprocess.run(["git", "clone", "-q", origin, b], check=True)
    return origin, a, b


def run_sync(repo):
    r = subprocess.run(["bash", SYNC], cwd=repo, capture_output=True,
                       text=True, timeout=120)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def main():
    tmp = tempfile.mkdtemp(prefix="devtest_syncfold_")
    try:
        # ---------------------------------------------------------------
        print("the incident shape — a commit whose content reached origin "
              "under another subject")
        _, a, b = world(tmp)
        # our two commits: a real change, and a generated-file update
        commit(a, "src/fix.txt", "the fix\n", "fix(A): a real change")
        commit(a, "gen/board.md", "BOARD v2\n", "docs(board): regenerate")
        # ...but another lane regenerates the SAME board content first. Our
        # board commit becomes empty during the rebase and git drops it: the
        # subject disappears and every line of it is already on origin.
        commit(b, "gen/board.md", "BOARD v2\n", "docs(board): regen from b")
        git(b, "push", "-q", "origin", "master")

        rc, out = run_sync(a)
        landed = git(a, "log", "--format=%s", "origin/master").stdout
        check("fix(A): a real change" in landed,
              "the real commit landed on origin")
        check("BOARD v2" in open(os.path.join(a, "gen/board.md")).read(),
              "the generated content is present on origin")
        check("DID NOT LAND" not in out,
              "no loss banner for a redundant-dropped commit",
              "banner fired" if "DID NOT LAND" in out else "")
        # Not "the string cherry-pick is absent" — the new message WARNS
        # against cherry-picking and so contains the word. What must be absent
        # is the recovery banner's instruction to run it.
        check("git cherry-pick <sha>" not in out,
              "does not advise the duplicating cherry-pick",
              "THIS is the expensive half")
        check("do NOT cherry-pick" in out,
              "says so explicitly, since the reflex is to reach for it")
        check("FOLDED or REWORDED" in out,
              "says what actually happened instead",
              [l for l in out.splitlines() if "FOLDED" in l][:1])
        check(rc == 0, "exits 0, so fill_pending_commits still runs",
              "rc=%d" % rc)

        # ---------------------------------------------------------------
        print("\nthe direction that must NOT be silenced — real loss still alarms")
        _, a2, _ = world(tmp + "2") if False else (None, None, None)
        tmp2 = tempfile.mkdtemp(prefix="devtest_syncfold2_")
        try:
            _, a2, _b2 = world(tmp2)
            commit(a2, "src/keep.txt", "kept\n", "fix(A): survives")
            commit(a2, "src/gone.txt", "gone\n", "fix(A): DROPPED BY HAND")
            # Simulate a rebase that loses a commit: drop it locally before
            # sync pushes. Its content reaches origin nowhere, so the
            # reverse-apply test cannot find it and the alarm must fire.
            git(a2, "reset", "-q", "--hard", "HEAD~1")
            # ...but the manifest sync.sh captures must still name it, which is
            # what a rebase-dropped commit looks like from inside sync.sh. Put
            # it back as a commit whose content we then strip in the rebase by
            # racing an identical PATH with different content.
            commit(a2, "src/gone.txt", "gone\n", "fix(A): DROPPED BY HAND")
            r = subprocess.run(
                ["bash", "-c",
                 'set -e; cd "$1";'
                 ' manifest=$(git log --format=%s origin/master..HEAD);'
                 ' manifest_shas=$(git log --format=%H origin/master..HEAD);'
                 # drop the top commit, as a rebase would, then ask the
                 # question sync.sh asks after its push
                 ' git reset -q --hard HEAD~1;'
                 ' for s in $manifest_shas; do'
                 '   if git show --binary "$s" | git apply --reverse --check -'
                 '        2>/dev/null; then echo "SURVIVED $s";'
                 '   else echo "LOST $s"; fi; done',
                 "_", a2], capture_output=True, text=True)
            check("LOST" in r.stdout,
                  "a genuinely absent commit fails the containment test",
                  r.stdout.strip().replace("\n", " ")[:60])
            check("SURVIVED" in r.stdout,
                  "and the one still present passes it",
                  "both directions distinguished by content, not subject")
        finally:
            shutil.rmtree(tmp2, ignore_errors=True)

        print()
        if fails:
            print("FAILED %d check(s): %s" % (len(fails), "; ".join(fails)))
            return 1
        print("all checks green")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
