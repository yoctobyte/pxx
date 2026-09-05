---
slug: bug-t-sync-sh-retries-a-push-whose-rebase-never-ran-and-calls-it-a-race
track: T
type: bug
prio: 40
status: open
found: 2026-09-05
found-by: frankC
owner: ""
blocked-by: []
summary: "push_with_retry() ignores rebase_onto_origin()'s result, and rebase_onto_origin() cannot detect a rebase that REFUSED TO START. `git rebase` aborting on `untracked working tree files would be overwritten` leaves ZERO unmerged paths, so the conflict loop's `[ -z \"$conflicted\" ] && break` treats it as resolved and returns. The push then fails non-fast-forward every time, and every iteration reports `push raced another writer` -- a diagnosis that is wrong, for a condition no number of retries can clear. Measured 2026-09-05: 42 attempts burned (12 then 30 via SYNC_PUSH_TRIES), all failing identically; the real error was only visible on a manual `git pull --rebase`, and the push succeeded on attempt 1 once the blocker was moved. THE FAILURE MESSAGE'S OWN ADVICE MAKES IT WORSE -- it says `raise SYNC_PUSH_TRIES`, which is exactly the wrong move here and is what I did. NOT the already-fixed exit-status bug (frankD, 2026-08-29): sync.sh correctly exits 1 and says YOUR WORK IS NOT ON ORIGIN. This is about the CAUSE it names, not about whether it reports failure."
---

# `sync.sh` retries a push whose rebase never ran, and calls it a race

## Reproduced, minimally, in a throwaway repo

Upstream commits `stray.txt`; the local clone has an **untracked** `stray.txt`
plus a local commit:

```
$ git rebase origin/master
Please move or remove them before you switch branches.
Aborting
error: could not detach HEAD

$ git diff --name-only --diff-filter=U      # unmerged paths
                                            # <- EMPTY
$ ls .git/rebase-merge .git/rebase-apply
none — rebase never started
```

## Why that defeats the retry loop

`rebase_onto_origin()` handles conflicts carefully, but every path in it is
keyed on **unmerged paths existing**:

```sh
conflicted=$(git diff --name-only --diff-filter=U)
[ -z "$conflicted" ] && break        # a rebase that never STARTED lands here
```

so it breaks out as if the rebase were resolved. `push_with_retry()` then does:

```sh
sleep "$(jittered_backoff "$tries")"
rebase_onto_origin                   # return value never checked
```

and loops. The tree has not moved, so the next `git push` fails identically.

**A retry loop whose precondition is broken has no exit except its budget.**

## What it costs, and why the message makes it worse

Tonight: `PUSH FAILED after 12 attempts`, then `after 30`. The advice in that
message is *"Re-run tools/sync.sh, or raise SYNC_PUSH_TRIES"*, so I raised it —
**strictly more wasted work, since no amount of retrying clears this.** Each
iteration is a fetch plus a failed rebase plus a failed push.

`push raced another writer` is a **diagnosis**, not an observation, and it was
false in every one of those 42 lines. The observation is "the push was rejected";
the cause was a rebase that could not begin.

## The fix is not the budget

Check `rebase_onto_origin`'s status, and have it distinguish *did not start*
from *finished cleanly*. `git rev-parse --verify HEAD` moving, or the absence of
`.git/rebase-merge` **together with** an unchanged merge-base, separates them.
When the rebase did not run, **stop immediately** and print git's own message —
which names the blocking files and is instantly actionable — instead of a race
that did not happen.

## Scope note

This is **not** the exit-status bug frankD fixed on 2026-08-29 (`push_or_die`).
That is working: sync.sh exits 1 and says `YOUR WORK IS NOT ON ORIGIN`, loudly.
This ticket is about **which cause it names** and **whether retrying can ever
help**.

Related, and the reason the precondition is not exotic: an untracked file
colliding with an incoming tracked one is what `git add -A` on a shared checkout
manufactures. That is how tonight's instance arose (`d1e332e1e`).

## One caller-side note, not part of the fix

`tools/sync.sh 2>&1 | tail -N` discards sync.sh's exit status — the pipe's
status is `tail`'s. The tool's own comment at `push_or_die` warns about exactly
this (*"ANY trailing command replaces the status"*), and I did it anyway in the
run that found this. The loud stderr text is what I actually reacted to, which
is an argument for keeping that text loud regardless of how this ticket is
fixed.
