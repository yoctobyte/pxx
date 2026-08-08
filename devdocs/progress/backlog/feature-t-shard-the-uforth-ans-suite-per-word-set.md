---
summary: "test-uforth is one monolithic job that now runs 13 ANS word sets and takes >15 min — shard it per word set so it parallelizes and a failure names the word set instead of timing out anonymously"
type: feature
track: T
prio: 55
---

# Shard `test-uforth`'s ANS suite per word set

- **Type:** feature (Track T — tier composition)
- **Found:** 2026-08-08, immediately after Track N enrolled all 13 ANS word
  sets (`1b1fbd259`, "13 of 13, enrolled and gated").

## What happens

`test-uforth` is a **single job**. It was 46s. Enrolling Gerry Jackson's 13
word sets — each run twice, native and CPython, for the differential — took it
past **15 minutes** on a loaded box.

It was classed `unit` (90s), so testmgr killed it and the watcher published
`test-uforth#00 = timeout` as a RED. That part is fixed (`394c4f217`
reclassifies it `corpus`, 1200s), but that only raises the ceiling:

- a direct `make test-uforth` was **still running at 15 minutes**, so 1200s may
  not clear it either — and `corpus` is already the second-longest budget;
- one job means **one timeout with no attribution**. `test-uforth#00 (timeout)`
  does not say which word set hung. The published report's log tail stops at
  "running the Forth 2012 / ANS suite per WORD SET" and tells you nothing more;
- one job means **no parallelism**, on a box sized to run 24 at once. The suite
  is embarrassingly parallel: the word sets are independent files.

## Fix shape

Shard it the way the C conformance matrix already is
(`CONFORMANCE_SHARDS` in `tools/testmgr.py`, `job.cls == "conformance"`):
one job per word set, `test-uforth#core`, `test-uforth#string`, and so on.

That buys, in order of value:

1. **attribution** — a red names the word set, and the stable selector means it
   can be bisected and ticketed like any other job;
2. **parallelism** — 13 short jobs instead of one 15-minute serial monolith;
3. **a working timeout** — each shard fits comfortably inside a normal budget,
   so the class question stops being marginal;
4. **partial credit** — 12 green word sets stay green when the 13th breaks,
   instead of the whole corpus reading as one red.

The Makefile already loops `UFORTH_CORPUS`; the shard boundary is that loop.

## Note

Not urgent while the suite is green — but the moment one word set regresses,
the watcher's report will say "timeout" and name nothing, which is the
diagnostic dead-end this ticket exists to prevent.

## Gate

`tools/testmgr.py --tier limited --list` shows one job per word set; a forced
failure in one word set reds only that shard.

## Update 2026-08-08 — the timeout half is fixed elsewhere; this is now about attribution

Measured after filing. Two corrections to the reasoning above:

**The cost is one file, not the suite.** The Makefile already records it:
`blocktest` is ~240s under pxx against CPython's ~80s (a memory-walk and hash
workload); *"the other twelve together are seconds"*. The 23m36s I measured was
on a box at load 15+ with a peer testmgr — idle it is ~6 minutes.

**`corpus` was never the binding constraint.** The budget is
`min(cls_to*scale, max(45, exp_dur*10+15, cls_to*scale/4))` — the hang detector,
not the class ceiling. test-uforth had learned `dur=17.75s` from five runs as a
four-corpus job, so its budget was **300s** regardless of class. Reclassifying
it `corpus` changed nothing.

That is fixed generally in `82585920b`: a timed-out job now raises its stored
expectation to the duration observed before the kill, so it converges to the
class ceiling in one cycle instead of being killed by a stale value forever.
**No sharding is needed to stop the false red.**

**What is still worth doing here**, in order:

1. **Attribution.** `test-uforth#00 (timeout)` names no word set, and the
   report's log tail stops at "running the Forth 2012 / ANS suite per WORD
   SET". A per-word-set shard gives a stable selector that can be bisected and
   ticketed like any other job.
2. **Parallelism**, on a box sized for 24 concurrent jobs — though note the win
   is bounded by blocktest, which is most of the wall time on its own.
3. **Partial credit** — twelve green word sets stay green when the thirteenth
   breaks.

Prio unchanged, urgency lower: this is now a diagnosability improvement, not a
fix for a recurring red.
