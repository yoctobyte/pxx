---
slug: grant-progress-py-to-pxx-a5-for-the-uncited-resolve-check
track: T
prio: 45
status: open
---

# GRANT: `tools/progress.py` → pxx-a5, scoped to the `UNCITED-RESOLVE` check

**Granted 2026-08-30.** `tools/progress.py` is every lane's tool on every ticket
move, which is why pxx-a5 correctly declined to edit it unasked and filed
`bug-t-a-resolve-that-never-wrote-a-placeholder-is-uncited-and-nothing-says-so`
[T p45] instead. The coordinator holds it and is the bottleneck; the design is
pxx-a5's, complete, with three cautions it derived itself. Granting rather than
re-implementing from a description.

**Scope:** the `UNCITED-RESOLVE` check inside `check()`, and its devtest. Nothing
else in the file. The coordinator is not editing `progress.py` while this is open.

## The defect

A ticket resolved by a **hand-written Log line** never gets a `PENDING-COMMIT`
placeholder — so `sync.sh` has nothing to fill and `check` has nothing to count. It
is uncited and **silent**, which is strictly worse than `PENDING-COMMIT`, a state
that at least greps, counts, and has a tool that knows how to repair it. Measured:
**3 of 681** in the 2026-08-16..31 window.

## The three cautions, all pxx-a5's, all load-bearing

1. **Warn, never repair.** `check`'s own bookkeeping note records that ~82% of bad
   citations *look* fixable by git-log matching and are not.
2. **A date floor.** 881 of 2806 `done/` tickets predate the convention and would
   flood it with 881 findings on day one — which is how a guard gets muted (129,
   and `STALE-EDGE-HIDDEN`'s calibration comment).
3. **Some resolutions are not commits.** *"Profiled; findings filed; two levers
   measured and declined"* is a real outcome, and **a check that flags it teaches
   people that uncited means nothing.**

Three distinct routes to the same worthless-check failure, which is why this is a
grant and not a ticket description.

## Convention it must encode

Ruled 2026-08-30: **for a HAND-FILLED citation, cite the FIX, not the close.** The
"cite the resolve commit" convention exists because that is what `sync.sh` can
automate at push time, not because the resolve commit is more useful. When a human
fills it and the two are distinguishable, cite what a future reader needs — what
changed — and name the close in the Log line. **The automated `resolve` +
`sync.sh` path is unchanged**; a placeholder can only ever know the resolve sha.
