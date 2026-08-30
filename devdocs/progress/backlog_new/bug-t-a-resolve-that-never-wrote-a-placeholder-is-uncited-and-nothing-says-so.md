---
track: T
prio: 45
type: bug
status: backlog_new
blocked-by: []
found: 2026-08-30
found-by: claude@plexus (Track T face 2), auditing the PENDING-COMMIT residue
summary: "check counts tickets that say PENDING-COMMIT. It has nothing to say about a resolved ticket that cites no commit AT ALL — no placeholder, no sha — which is the strictly worse state, because the placeholder is the thing that announces itself. 3 of 681 tickets resolved 2026-08-16..31 are in it, all resolved by a hand-written Log line rather than `progress.sh resolve`."
---

# A resolve that never wrote a placeholder is uncited, and no instrument says so

## The measurement

`check` currently reports **zero** PENDING-COMMIT — verified two ways
(`check --strict` lists none; `progress.sh pending` prints nothing). The
citation loop is working.

But `check`'s pending scan can only see tickets that **say** `PENDING-COMMIT`.
A ticket resolved by hand — the Log line typed directly instead of through
`progress.sh resolve` — never gets a placeholder, so `sync.sh` has nothing to
fill and `check` has nothing to count. It is uncited and silent.

Scanning `done/` for tickets with a Log entry dated 2026-08-16..31 and no sha
anywhere in the file:

```
3 of 681
  bug-t-the-breadth-banner-vouches-for-cross-targets-on-a-run-that-covers-none
  feature-t-expect-same-a-recipe-assertion-that-prints-its-mismatch
  perf-t-where-the-matrix-actually-spends-its-time
```

All three carry a hand-written Log line (`— fixed with guards; resolved.`,
`— helper landed with guards; resolved.`, `— profiled; findings filed`). None
ever held a placeholder.

**This is the strictly worse state.** `PENDING-COMMIT` is loud: it is a string
that greps, a count that a check reports, and a thing a tool knows how to
repair. A missing Log citation is indistinguishable from a ticket nobody has
finished citing yet, and there is no signal at all.

## Proposed check

`UNCITED-RESOLVE: <slug> is in done/ and cites no commit` for a ticket in a
resolved status whose body carries no sha-bearing citation **and** no
`PENDING-COMMIT`. Two cautions the existing code already learned the hard way:

- **Warning, never repair.** `check`'s own note on bookkeeping citations says it:
  *"Fix by hand with the ticket open — do not bulk-match against git log"*, on
  the recorded evidence that ~82% of bad citations look fixable that way and are
  not. This check reports and stops.
- **Historical tickets must not flood it.** 881 of 2806 `done/` tickets carry no
  citation, nearly all predating the convention. The scan needs a date floor or
  a `--strict`-only gate, or it is 881 findings on day one, which is how a guard
  gets muted — the failure this repo has recorded more than once.

## What was filled, and what was left

- **Filled:** `feature-t-expect-same-...` → `b194ef7ec`. The ticket's title is
  verbatim the commit subject, and an **unbounded** `git log --format=%s
  origin/master | grep -cF` returns exactly **1**.
- **Left for its owner:** `bug-t-the-breadth-banner-...` has **two** exactly-1
  candidates and they mean different things — `62dd38d65` *"fix(T): the breadth
  banner reads the full TIER, not the last replacing run"* (the fix) and
  `0d0230593` *"ticket(T): close the breadth-banner bug; record why the ratio
  ticket stays open"* (the close). Convention says a resolve cites the commit the
  **resolve** landed as, which argues for the close; usefulness argues for the
  fix. That is a convention question, not a lookup — owner `pxx-a5`.
- **Left, unmatchable:** `perf-t-where-the-matrix-actually-spends-its-time`
  resolved as *"profiled; findings filed to the owning lane; two levers measured
  and declined"*. There may be no code commit to cite. Owner `pxx-aa`.

## Why this is filed and not built

The check lives in `tools/progress.py`, which is every lane's tool on every
ticket move rather than Track T's file — the same boundary that sent
`chore-t-board-html-render-is-13s-of-every-ticket-move` to its owner.

Related: `bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two`
(resolved — the placeholder half, which is why the count is 0 today) and
`tools/sync_pending_commit_devtest.py`, whose `prose-mention-is-not-rewritten`
guard already pins the false-positive direction.
