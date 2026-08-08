---
summary: "The full tier grew from ~520s to the 3600s global deadline once test-uforth carried the 13 ANS word sets, so it is being TRUNCATED every run — and auto-pin shadow mode, which only evaluates on a full tier, never evaluates at all"
type: bug
track: T
prio: 65
---

# The full tier no longer fits its deadline, so it is truncated every run

- **Type:** bug (Track T — tier composition / `tools/testmgr.py`)
- **Found:** 2026-08-08 while verifying the test-uforth fixes.

## Measured

Full-tier wall on plexus, from `tstate/runs-plexus.ndjson`:

| when | wall | verdict |
|---|---|---|
| 2026-08-08T15:22 | 544.1s | GREEN |
| 2026-08-08T16:02 | 516.2s | GREEN |
| 2026-08-08T17:00 | 596.0s | RED |
| 2026-08-08T18:54 | **1753.1s** | RED |
| 2026-08-08T19:30 | **1753.2s** | RED |
| 2026-08-08T20:45 | **3600.3s** | RED |

`--deadline` defaults to **3600**. That last run did not take an hour — it was
**cut off at one**, and `testmgr` marks every unlaunched job `skipped` and tears
down.

## Why it grew

`test-uforth` was 46s when it was enrolled in limited+full
(feature-t-enroll-uforth-in-the-tiers). Track N then enrolled Gerry Jackson's
13 ANS word sets (`1b1fbd259`), each run twice for the differential, taking the
single job to ~6 min idle and 23m36s under load. Two Track T fixes then
correctly let it run to completion rather than being killed early
(`394c4f217` class, `82585920b` the stale-metric trap) — which is right, and
which is also what surfaced the real cost.

## What is and is not broken

**Not laundered, at least.** Unlaunched jobs get status `skipped`, and the
report-json omits `queued`/`skipped` jobs entirely, so twatch's merge keeps each
one's previous verdict rather than inventing a pass. The honesty machinery
holds.

**But coverage silently degrades.** The tier's whole purpose is breadth. A tier
that reliably runs out of clock is testing a prefix of itself, and which prefix
depends on scheduling order, not on what changed.

**And it blocks auto-pin.** `pin_shadow()` only evaluates on `PIN_TIER = "full"`
(decide-track-t-autopin-criteria, option A, shadow mode). No full tier has
completed since 20:45, so `plexus.json` still reads
`pin_shadow: not evaluated yet`. The shadow week cannot start until a full tier
can finish.

## Options

1. **Shard test-uforth per word set**
   ([[feature-t-shard-the-uforth-ans-suite-per-word-set]]). 13 short parallel
   jobs instead of one 20-40 min serial monolith. Best fix; the Makefile notes
   `blocktest` alone is ~240s of it, so even sharded that one stays the pole.
2. **Raise `--deadline` for the full tier.** Cheapest, and honest if an hour is
   genuinely too short for what full now contains — but it hides the growth
   rather than paying for it, and the watcher's cycle time is already why
   `full` backfills keep getting preempted by new pushes.
3. **Move test-uforth to `limited` only**, out of `full`. Wrong direction:
   `limited` is not smaller in wall time here, and it would lose the ANS
   coverage from the broadest tier.
4. **Put `blocktest` in its own job / drop it from the tier corpus.** It is
   ~240s under pxx vs ~80s under CPython for a memory-walk and hash workload.
   Worth asking whether the differential earns that on every full run.

Recommend **1**, with **2** as a stopgap if the shadow week is wanted sooner.

## Gate

A full tier that completes inside its deadline on an idle box, and
`plexus.json` showing a `pin_shadow` verdict rather than "not evaluated yet".
