---
slug: bug-t-livejson-published-100pct-for-every-interrupted-run
track: T
type: bug
prio: 50
status: done
blocked-by: []
summary: "testmgr's final `live.json` write hardcoded `pct: 100.0` and counted progress with `done_count()`, which counts the jobs teardown marks `skipped`. Every INTERRUPTED run therefore published `done == total, pct 100.0`. Measured instance: a full tier preempted after deciding 108 of 2765 jobs published `2765/2765, 100%`. The defect is as old as live.json itself (f0f603463, 2026-07-08) — six weeks of history in which an aborted run is indistinguishable from a finished one to anything reading progress."
owner: plexus-T
---

# live.json published 100% for every INTERRUPTED run

## The finding

`tools/testmgr.py` writes `.testmgr/live.json` twice: a progress record during the
run (`:2357`) and a final record at exit (`:4036`). The in-run one is careful — it
caps at `min(99.0, ...)` precisely so a live run never reads as finished. The final
one hardcoded the opposite:

    "ts": time.time(), "tier": args.tier, "pct": 100.0,
    "done": mgr.done_count(), "total": len(jobs),

Both halves are wrong on an abort, and they are wrong in the same direction:

- `pct: 100.0` is unconditional — it is a statement about *reaching the end of
  `main()`*, not about finishing the tier;
- `done_count()` (`:2679`) counts `("pass","fail","timeout","skipped")`, and
  `teardown()` marks **every un-launched job `skipped`**. So the moment the run is
  interrupted, `done_count()` converges on `len(jobs)` by construction.

On SIGINT the run still reaches the final write (that is what makes the report
survive, and what shape 2 now depends on). So an interrupted run published a
completeness record that a completed run could not be distinguished from.

## Measured

2026-08-19 ~18:07, a `full` tier on `bb4cb0065` was preempted by a push after
**272.2s wall, 108 of 2765 jobs decided**. Its `live.json`:

    {"tier": "full", "pct": 100.0, "done": 2765, "total": 2765, "verdict": "INTERRUPTED"}

`verdict` was correct. Nothing lied to a reader who read `verdict` — and every
reader of `done`/`total`/`pct`, which is what a progress display is *for*, saw a
finished full tier. This is how the run was nearly mis-credited as breadth
coverage during shape 2 review: the numbers said a full tier had completed.

## How far back it goes

`git log -S '"pct": 100.0' -- tools/testmgr.py` gives exactly two commits: the fix
below, and **f0f603463 (2026-07-08)**, the commit that introduced `live.json`. The
`skipped`-counting `done_count()` predates it (`bddb40c55`) and was unchanged
throughout. The `INTERRUPTED` verdict also arrives in f0f603463.

**So the defect is coeval with the file: every INTERRUPTED run ever recorded in
live.json published `done == total` at `pct: 100.0`, from 2026-07-08 to
2026-08-19.** Anyone re-reading old `live.json` history — or any frontend that
sampled it — must treat completeness on an aborted run as unreadable for that
window; only `verdict` and the job list in the report carry the truth. Note this
also means the historical record cannot be repaired: the real decided-count for
those runs was never written down anywhere.

## Fix

`live_progress(jobs)` (`tools/testmgr.py:1452`) counts only genuinely decided
statuses (`pass`/`fail`/`timeout`), derives `pct` from that, and reaches 100.0 only
when `decided >= total`. Both the final write and the `pct` come from it.
`done_count()` is left alone — it has other callers for which counting the
teardown-skipped jobs is right; the bug was using it as a *progress* number.

Guarded by `tools/twatch_resume_devtest.py:161` (`live_progress` checks: a
teardown-`skipped` job does not count toward `done` and does not move `pct` — 3 of
10 reads as 3/10 at 30.0, not 10/10 at 100.0; a run that really finished still
reports 100.0; an empty job set does not divide by zero).

Shipped in `e2449adc5` alongside shape 2, which is how it was found — not part of
the resume story otherwise.

## Log
- 2026-08-19 — resolved, commit e2449adc5.
