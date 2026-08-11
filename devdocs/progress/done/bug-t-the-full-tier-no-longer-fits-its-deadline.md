---
summary: "DOWNGRADED: the 3600s truncation was ONE run inflated by the uforth driver collision, not a permanent size problem — a full tier completed GREEN in 768s once that was fixed. What remains is watching the growth from ~520s to ~768s"
type: bug
track: T
prio: 45
status: done
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


---

## CORRECTION 2026-08-09 — downgraded from urgent (prio 65 -> 45)

**I was wrong about the cause, and the ticket overstated the problem.**

A full tier completed **GREEN in 768s** at 2026-08-09T01:43:38Z. The tier fits
its deadline comfortably.

The 3600.3s run was **one run** inflated by the `test-uforth` driver collision
([[bug-t-make-test-uforth-drivers-are-not-concurrency-safe]] — fixed in
`6f54e33f7`): a concurrent manual run deleted the watcher's in-flight drivers
via an unscoped glob, so uforth churned instead of finishing. The 1753s runs
sit either side of the same window. Reading three contaminated samples as a
trend was the error.

**And the second claim was wrong too.** "auto-pin shadow mode never evaluates"
was attributed to the tier not finishing. The real reason: `twatch.py` is read
once at process start and has **no hot reload**, and the daemon had been
running since Aug 7 18:51 — before `pin_shadow` existed. `testmgr.py` changes
went live immediately (spawned per run, which is why test-uforth got fixed),
`twatch.py` changes did not. Restarted 2026-08-09T05:02; shadow mode evaluates
on the next full tier.

**What genuinely remains**, and why this stays open at a lower priority: the
full tier did grow from ~520s to ~768s, and `test-uforth` is most of that. The
options below still apply — sharding is still the right call for attribution
and parallelism — but this is capacity planning, not a fire.

---

## RESOLVED 2026-08-11 — option 1 landed; the growth is paid back with margin

Both halves of this ticket's gate are met, and the recommended structural fix
is in.

**Gate, first half — "a full tier that completes inside its deadline".** It
does, and has for days. From `tstate/runs-plexus.ndjson`, the last 35 full-tier
runs: min 622.6s, median **770.9s**, max 810.0s, against a 3600s deadline. No
truncation since the driver-collision window this ticket originally
misdiagnosed.

**Gate, second half — "`pin_shadow` showing a verdict rather than 'not
evaluated yet'".** It has been deciding continuously since the 2026-08-09
restart; `tstate/pin-shadow.log` carries a 13-deep streak of qualifying shas as
of 2026-08-11T15:22.

**Option 1 has now landed** ([[feature-t-shard-the-uforth-ans-suite-per-word-set]]):
`test-uforth` is 14 shards, and the CPython oracle runs concurrently with the
pxx run. Measured cause, which is what closes the capacity question rather than
just the deadline one:

| tier | total work | longest single job | wall floor |
| --- | --- | --- | --- |
| limited | 1064s | `test-uforth#00` 791s | max(791, 89) |
| full | 1967s | `test-uforth#00` 791s | max(791, 164) |

The tier was not short of clock — it was short of *parallelism*, with 74% of
`limited`'s entire work in one serial job. Projected wall after sharding is
~270s for both tiers, so the ~520s→~768s growth this ticket asked to watch is
repaid several times over.

Option 4 ("drop blocktest — does the differential earn its cost?") is
**declined, and re-filed as the real question it was pointing at**: blocktest
is slow because pxx-compiled code loses to CPython by 2-4x on every uforth
subject measured, which is a compiler bug worth having rather than a test worth
dropping — [[bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython]].
Coverage stays; the cost gets fixed at its source.

Real walls land in `tstate` on the next full run carrying the shard commit.

## Log
- 2026-08-11 — resolved, commit c488470af.
