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

## Repro

Two local commits, a `BOARD*.md`-touching commit landing on origin between
them, and a second `sync.sh` running concurrently. Not deterministic; the
reflog signature above (`commit (amend)` inside a rebase) is the reliable tell
after the fact.

## Related
- [[bug-c-a-multidim-array-field-decays-with-the-element-stride]] — the ticket whose commit message this ate
- [[bug-t-resolve-cites-a-sha-the-rebase-then-rewrites]] — same file, same contention, different symptom
