---
track: T
prio: 45
type: bug
blocked-by: []
summary: "With several checkouts syncing at once, tools/sync.sh's rebase-and-retry loop squashed two separate commits into one: the second commit's content survived, its message and its `resolves:` line did not. Silent — the tree is clean, the push succeeds, and the only tell is a `git log` one shorter than expected."
---

# Concurrent sync.sh runs can squash two commits into one

- **Type:** bug (silent history loss) — **Track T** (`tools/sync.sh`).
- **Observed:** 2026-08-30, frankC, pushing two Track C commits.

## What happened

`5348f20ef` (a refactor) and `34a72721c` (a fix) were committed separately and
pushed with one `tools/sync.sh`. Four `sync.sh` processes were live at the time
across sibling checkouts (frankB and frankC both syncing, plus retries), and
`BOARD.md` / `BOARD-brief.md` conflicted on every attempt — they are generated
files that every lane rewrites.

The retry loop worked through it and pushed. What landed was **one** commit,
`72de20420`, carrying the union of both diffs under the *first* commit's
message. Reflog shows the shape:

```
ac01163a9 rebase (finish)
ac01163a9 rebase (continue): fix(C+A): a multi-dim array FIELD ...
148fb937a rebase (continue): refactor(C+A): the partial-index sentinel ...
...
380ec29c8 commit (amend): refactor(C+A): the partial-index sentinel ...   <-- here
058ec11d7 rebase (continue): refactor(C+A): the partial-index sentinel ...
```

An `amend` during a later conflicted pass folded the second commit's content
into the first.

## Why it is worth fixing rather than shrugging at

- **No error, no dirty tree, exit 0.** The push succeeds and everything builds.
  The only symptom is a `git log` one commit shorter than the author expects,
  which nobody checks after a successful push.
- **It costs exactly the thing commits are for.** The content was fine — the
  code was verified intact at HEAD afterwards. What was lost was the second
  commit's *message*: its measurements, its `resolves:` line, and the
  separation that lets a later bisect land on one change rather than two.
- **`resolve` citations silently double up.** Two tickets now cite one sha, and
  that sha's message describes one of them. Nothing detects this.
- **It is most likely exactly when it hurts most:** many lanes active, i.e.
  when history is most worth keeping straight.

## Suggested direction

Two candidates, cheapest first:

1. **Never let the retry path amend.** If the loop resolves a conflict, it
   should `rebase --continue` only, and abort loudly if a `commit --amend`
   would be needed. Losing a push to a clear error beats winning one that
   silently merges two commits.
2. **Stop `BOARD*.md` conflicting at all** — it is the trigger every time.
   These are generated (`tools/progress.sh board-md`); a merge driver that
   simply regenerates them from the ticket tree post-rebase would remove the
   whole conflict class. That helps every lane, not just this failure.

A cheap guard while neither is done: `sync.sh` records the commit count before
the rebase and warns if fewer commits were pushed than were staged for push.

## How to check whether it hit you — and what is NOT the tell

**`commit (amend)` inside a rebase is NOT the signature.** `sync.sh` amends
deliberately as part of its documented job: filling in the sha a `resolve`
landed as, which is the entire reason `resolve` writes `PENDING-COMMIT`. One
coordinator reflog carried **38** of them in a single night. Grepping for that
alone will tell most of the fleet they lost work.

The signature is an amend that **reduces the commit count** — one whose parent
is not the commit being amended. Operationally, and much cheaper:

**Count your commits on origin afterwards, and check by CONTENT, not by sha.**
A sha that is absent from `origin/master` is the *normal* outcome of a rebase,
not evidence of loss: the coordinator found two of six shas missing and both
had landed intact under new shas with their own messages. Six commits in, six
distinct messages out, nothing lost. Checking by sha and stopping there would
have produced a duplicate of this ticket filed against a healthy push.

So the check is: **N commits pushed, N distinct messages on origin.** That is
what caught this one — the code was all present, and the count was one short.

## Repro

Two local commits, a `BOARD*.md`-touching commit landing on origin between
them, and a second `sync.sh` running concurrently. Not deterministic.

## Related
- [[bug-c-a-multidim-array-field-decays-with-the-element-stride]] — the ticket whose commit message this ate
- [[bug-t-resolve-cites-a-sha-the-rebase-then-rewrites]] — same file, same contention, different symptom

## Second loss, two hours later, DIFFERENT signature: a commit dropped entirely

2026-08-30. Not a squash. `sync.sh` **dropped a whole commit and pushed another
lane's instead**, reporting success.

```
55b08dc7f HEAD@{8}: commit: fix(C): sizeof of a partial index ...
fe90725fc HEAD@{7}: rebase (start): checkout origin/master
fe90725fc HEAD@{6}: rebase (finish): returning to refs/heads/master
```

Four consecutive `rebase(start)`/`rebase(finish)` pairs, each landing on origin's
tip, **never replaying the local commit**, leaving the branch pointing at origin.
Then `sync: pushed — <another lane's subject>`.

**Every available signal said success:** `git rev-list --count
origin/master..HEAD` = 0, exit code 0, clean tree. Recovered by cherry-pick out
of the reflog; without a by-hand content check the work would have survived only
until the reflog expired.

### Two mechanisms, deliberately not merged

The C lane reported its own share honestly and refused to blur them:

1. **Caller error, owned and avoidable:** it edited `compiler/cparser.inc` while
   a **backgrounded** `sync.sh` was running. The tree was clean when sync
   started, so nothing refused, and the rebase then checked out over a live
   working tree. **This explains the lost WORKING TREE.**
2. **Unexplained:** it does **not** explain the lost COMMIT, which existed
   before sync started and which a rebase should have replayed.

*"A cause that explains most of the evidence"* is the dangerous kind, because it
retires the investigation. Half a diagnosis presented whole would have shipped a
"do not edit during sync" warning as the fix with the drop mechanism still live.

### Landed: a net, not a cure

`sync.sh` now captures a **manifest of commit subjects before the first rebase**
and, after the push, fetches and confirms every one is on origin — naming what is
missing, stating the work is in the reflog, printing the cherry-pick recipe,
saying **not** to `reset --hard`, and exiting non-zero.

**By SUBJECT.** Checking by sha manufactures false alarms: an ordinary rebase
rewrites every sha, so a missing sha is the *normal* result. The coordinator
nearly filed one against itself doing exactly that. Exit code, ahead-count and
tree state catch **neither** loss, because all three are what a healthy push also
leaves behind.

It also **stops printing `HEAD` as the success line** — HEAD after a rebase is
frequently another lane's commit, and printing it is *how* the drop read as a
success.

### Third symptom of the same contention, filed separately at the time

The retry budget exhausting (6 → raised to 12). Reported as a knob and treated as
one; in hindsight it was the same busy-tree contention as both losses. **Three
failures of one tool in one night, all in the push/rebase path, none reproducible
before eight lanes were live.**

The proposed `BOARD*.md` merge driver remains the better fix than any of this: it
removes the conflict class rather than one failure path.
