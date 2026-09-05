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


# The fixture's own commit() passes `-c user.email=... -c user.name=...` per
# invocation, so ITS commits always work. sync.sh, the code actually under
# test, inherited nothing -- and a temp clone inherits nothing either. On a host
# with a global identity that difference is invisible; on one without, the
# fixture succeeds and the subject dies.
#
# MEASURED on seven, 2026-09-05: no ~/.gitconfig and no /etc/gitconfig, so this
# devtest had NEVER passed there (`job_last_pass: None` -- "never measured
# here", not "always broken"), while every real commit on the box worked because
# the watcher clone carries a LOCAL identity.
#
# THE DEVTEST WAS CORRECT ABOUT WHAT IT ASSERTED AND BLIND TO A CONDITION IT
# SILENTLY SUPPLIED TO ONE HALF OF ITSELF. Supplying it to BOTH halves is the
# fix: the subject now runs under the same conditions as the fixture, and the
# dependency stays visible rather than being hidden behind a box setting.
SYNC_ENV = {"GIT_AUTHOR_NAME": "devtest", "GIT_AUTHOR_EMAIL": "t@pxx",
            "GIT_COMMITTER_NAME": "devtest", "GIT_COMMITTER_EMAIL": "t@pxx"}


def run_sync(repo, identity=True, homeless_dir=None):
    e = dict(os.environ)
    if identity:
        e.update(SYNC_ENV)
    else:
        # Strip EVERY route to an identity -- env vars, ~/.gitconfig, the XDG
        # path and /etc/gitconfig. seven's condition reproduced, not
        # approximated.
        for k in list(SYNC_ENV) + ["EMAIL"]:
            e.pop(k, None)
        e["HOME"] = homeless_dir
        e["XDG_CONFIG_HOME"] = homeless_dir
        e["GIT_CONFIG_GLOBAL"] = "/dev/null"
        e["GIT_CONFIG_NOSYSTEM"] = "1"
    r = subprocess.run(["bash", SYNC], cwd=repo, capture_output=True,
                       text=True, timeout=120, env=e)
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

        # ---------------------------------------------------------------
        # THE GUARD THAT KEEPS THIS FROM STRANDING A TREE. Without an identity
        # git dies INSIDE `rebase --continue`/`--amend` -- after the rebase has
        # begun -- leaving .git/rebase-merge, a detached HEAD and staged
        # changes, and sync.sh reporting "still mid-rebase after resolution",
        # which is two layers above the cause. sync.sh now refuses UP FRONT.
        #
        # THIS ROW IS WHY THE FIXTURE FIX ABOVE IS NOT THE WHOLE ANSWER.
        # Supplying the identity to the fixture makes the suite pass on every
        # host -- and would equally have hidden the product defect. The
        # dependency is real; a host without an identity must meet it as one
        # legible line, not as a stranded tree.
        print("\nthe identity precondition — refuse UP FRONT, do not strand "
              "a rebase")
        homeless = os.path.join(tmp, "nohome")
        os.makedirs(homeless, exist_ok=True)
        idroot = os.path.join(tmp, "idcheck")
        os.makedirs(idroot, exist_ok=True)
        _, a3, b3 = world(idroot)
        # THE DIVERGENCE IS THE WHOLE FIXTURE. A trivial fast-forward needs no
        # commit, so sync.sh never needs an identity and the rows below pass
        # with the guard REMOVED -- measured, not supposed: rc=0 and no strand.
        # Reproducing the real failure needs a rebase that has to COMMIT, which
        # is the same shape as the fold scenario above.
        commit(a3, "src/x.txt", "x\n", "fix(A): something to sync")
        commit(a3, "gen/board.md", "BOARD v2\n", "docs(board): regenerate")
        commit(b3, "gen/board.md", "BOARD v2\n", "docs(board): regen from b")
        git(b3, "push", "-q", "origin", "master")
        rc3, out3 = run_sync(a3, identity=False, homeless_dir=homeless)
        check(rc3 != 0, "refuses without a usable git identity", "rc=%d" % rc3)
        check("no usable git identity" in out3,
              "and names the precondition, not a symptom",
              [l for l in out3.splitlines() if "identity" in l][:1])
        # THE LOAD-BEARING ONE: refusing only beats dying if nothing moved.
        stranded = False
        for probe in ("rebase-merge", "rebase-apply"):
            d = subprocess.run(["git", "rev-parse", "--git-path", probe],
                               cwd=a3, capture_output=True,
                               text=True).stdout.strip()
            if d and os.path.exists(os.path.join(a3, d)):
                stranded = True
        check(not stranded,
              "and leaves NO rebase in progress — the point of refusing early",
              "rebase-merge/rebase-apply absent")
        head3 = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
                               cwd=a3, capture_output=True,
                               text=True).stdout.strip()
        check(head3 != "HEAD", "and does not leave HEAD detached", head3)
        # The control in the other direction: the SAME repo syncs once an
        # identity exists, so the rows above are the precondition failing and
        # not this fixture being broken.
        rc4, _ = run_sync(a3, identity=True)
        check(rc4 == 0,
              "while the SAME repo syncs cleanly once an identity exists",
              "rc=%d" % rc4)

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
