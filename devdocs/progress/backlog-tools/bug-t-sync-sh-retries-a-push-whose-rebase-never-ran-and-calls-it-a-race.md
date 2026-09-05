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

## The bug is the FALSE DIAGNOSIS. The retry budget is a symptom.

Every iteration prints:

```
sync: push raced another writer — rebasing and retrying (n/N)
```

That is a **diagnosis, not an observation.** The observation is "the push was
rejected". The cause, in the case this ticket is about, is a rebase that **could
not begin** — and it was false in all 42 lines it produced on 2026-09-05.

**A wrong mechanism printed 42 times is worse than no message**, because the next
reader inherits it as evidence. Raising the budget does not change the number of
true statements it makes; it raises the number of false ones.

**An empty unmerged set means BOTH "resolved cleanly" and "never ran".** That is
the expected-value-collides-with-the-failure-value shape: the value the code
tests for is also the value the failure produces, so the test cannot separate
them. See "would this still pass if the machinery did nothing".

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

## ONE CHAIN, NOT TWO COINCIDENCES — and it constrains how a fix is verified

The precondition — an untracked file colliding with an incoming **tracked** one
— is exactly what `git add -A` on a shared checkout manufactures. That is how
this instance arose: my own commit (`a409e19b5`) swept two scratch files onto
origin, and the untrack commit that fixed it (`d1e332e1e`) was the one that
could not push. **The bug created its own precondition.**

Two consequences for whoever takes this:

1. **It is not rare.** A reader who sees only the loop will judge it a freak
   contention event. It needs one session to commit a file another session has
   untracked, which is the normal state of a shared checkout with scratch in it.
2. **A fix verified on a tree where the precondition CANNOT OCCUR has not been
   verified.** Checking `rebase_onto_origin`'s status and re-running a normal
   contended push proves nothing about this path — the rebase succeeds, so the
   new check never fires. **The positive control has to be the blocked rebase
   itself**: an untracked file that collides with an incoming tracked one, which
   the throwaway-repo recipe above sets up in six commands.

## One caller-side note, not part of the fix

`tools/sync.sh 2>&1 | tail -N` discards sync.sh's exit status — the pipe's
status is `tail`'s. The tool's own comment at `push_or_die` warns about exactly
this (*"ANY trailing command replaces the status"*), and I did it anyway in the
run that found this. The loud stderr text is what I actually reacted to, which
is an argument for keeping that text loud regardless of how this ticket is
fixed.

**A THIRD VARIANT, and the diagnostic is what destroys the status** (frankS,
2026-09-05, isolated after its first-reported mechanism was measured not to
produce its observation). `cmd; echo "rc=$?"` — the idiom people reach for in
order to OBSERVE a status — prints the truth and exits 0, because the compound's
status is the trailing command's. Measured:

```
$ out=$(bash -c 'timeout 5 false >/dev/null 2>&1; echo "rc=$?"'); echo "$out $?"
rc=1 0                    <- printed 1, exited 0

on failure: 0             <- the positive control, and it is the whole finding
on success: 0
```

**It cannot report nonzero**, so any consumer reading the STATUS rather than the
output — a background-task notification, a wrapper, a CI step — sees success
unconditionally. Not the pipe: no pipe is involved, and `; true` does it too, so
it is `sync.sh`'s own *"ANY trailing command replaces the status"* wearing a new
costume, where the trailing command is the diagnostic itself. Fix is `rc=$?` on
its own line, then `exit $rc`. Recorded here rather than as its own ticket
because there is no committed caller to fix — the code half of this was already
swept to zero (LOGBOOK 2026-08-31, funnel 89 -> 0), and CLAUDE.md already tells
agents to grep a backgrounded gate's LOG for the verdict rather than trust the
wrapper's exit code, in those words.

## The two candidate discriminators, MEASURED — one of them cannot fire here

Offered by frankS, 2026-09-05. Run against the throwaway repro above rather than
reasoned about, because both sound equally plausible and only one is an
instrument for THIS failure.

| probe | clean tree | after the rebase that REFUSED TO START |
| --- | --- | --- |
| `.git/rebase-merge` / `.git/rebase-apply` exist | absent | **absent** |
| `git rev-list --left-right --count origin/master...HEAD` | `0 0` | **`1 1`** |

**The rebase directory is NOT a discriminator for this bug.** It separates *a
rebase in progress* from *no rebase in progress* — and a rebase that never began
is in the second group, exactly like one that finished cleanly. It is the same
shape as the unmerged-path test it would replace: the value it reads on the
failure is the value it reads on success, so it is a guard that cannot fail.
Using it alone would swap one collision for another. (My "absence of
`.git/rebase-merge` **together with** an unchanged merge-base" above is only
sound because of the second clause; the first clause carries nothing.)

**The two probes answer different questions, and only one of them is about this
bug.** "Is a rebase in progress" is a real question with a real use; it is just
not the question here, and the rebase-dir check answers it correctly. Rejecting
it is not a claim that it is broken — it is a claim that it is aimed elsewhere.

**`--left-right --count` is the right instrument** and is better than the
merge-base phrasing above: it answers *did the tree actually move* in one
command, needs no before/after capture, and `left > 0` after a rebase the loop
believes succeeded is precisely the impossible state. Prefer it in the fix.
