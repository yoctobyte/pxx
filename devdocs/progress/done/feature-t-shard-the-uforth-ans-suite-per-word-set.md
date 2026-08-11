---
summary: "test-uforth is one monolithic job that now runs 13 ANS word sets and takes >15 min — shard it per word set so it parallelizes and a failure names the word set instead of timing out anonymously"
type: feature
track: T
prio: 55
status: done
owner: claude@plexus
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

## RESOLVED 2026-08-11 — sharded; and it was a WALL-TIME fix after all

The update above downgraded this to "diagnosability, parallelism bounded by
blocktest". Measured, that reading was too pessimistic about the value: the
bound is real, but the job was setting the wall time of **both tiers it is
enrolled in**, so removing it is the largest single speed-up available to
Track T.

**Where the tiers' time actually goes** (learned EWMA, `.testmgr/metrics.json`,
12-core plexus):

| tier | jobs | total work | longest single job | work/12 cores |
| --- | --- | --- | --- | --- |
| limited | 1758 | 1064s | **`test-uforth#00` 791s** | 89s |
| full | 2268 | 1967s | **`test-uforth#00` 791s** | 164s |

A tier's wall cannot go below `max(longest job, work/cores)`. For `limited`
that is `max(791, 89)` — **74% of the tier's entire work sat in one serial job
while eleven cores idled.** Observed walls (limited ~790s, full 771s median)
match the model exactly.

**Where test-uforth's own time goes** (measured per phase, this session,
compiler at `96b4b40ab`; box contended by the watcher, so absolutes run high —
the shape is what matters):

```
compile uforth.py            27.8s
4 corpora                    12.0s pxx +   3.7s cpython
12 non-blocktest word sets   50.3s pxx +  15.4s cpython
blocktest.fth               413.3s pxx + 196.0s cpython   <-- 85% of the job
                            -------------------------------
                            measured serial total 719.5s (EWMA says 790.7s)
```

So the Makefile comment was right that blocktest is nearly all of it, and the
per-word-set shard is still the correct boundary — it just does more than give
attribution.

**Landed:**

1. **Sharded per word set** — 14 jobs (13 word sets + one for the uforth-native
   corpora) replacing `test-uforth#00`. Done WITHOUT a second copy of the word
   list in Python: a new `print-%` rule in the Makefile lets `testmgr` ask make
   for `UFORTH_WORDSETS`, so adding a word set adds a shard by itself. If make
   cannot be asked, it falls back to one unsharded job — a slow tier is a cost,
   a guessed list is a coverage lie.
2. **The CPython oracle now runs CONCURRENTLY with the pxx run**, joined by
   `wait`. They are independent, so the oracle came off the critical path
   everywhere — 196s of blocktest's 609s here. Deliberately NOT cached across
   runs: a stale oracle turns a real regression into a false green.
3. Both loops tolerate an EMPTY list, which is what makes a shard expressible
   (`for f in ; do` is a shell syntax error, not an empty loop).

**Projected effect on the wall**, using the Makefile's uncontended ~240s
blocktest: the pole becomes one `27.8 + 240 ≈ 268s` shard, every other shard is
~28-36s (dominated by the compile each shard repeats).

| tier | wall before | wall after (projected) |
| --- | --- | --- |
| limited | ~790s | ~270s |
| full | 771s | ~270s |

~2.9x on both. The real number lands in `tstate` on the watcher's next full
run against a sha carrying this commit — that is T's own evidence loop, and it
should be read there rather than trusted from here.

**The compile is now repeated 14x** (~390s of extra CPU). Deliberate: the box
has ~10 idle cores behind the old pole, and the trade buys a wall bounded by
the slowest word set instead of their sum.

**Verified** (the gate this ticket asked for):
- `testmgr --tier limited --list` shows one job per word set
  (`test-uforth#blocktest`, `#stringtest`, ...); every tier still generates
  (+13 jobs each);
- both shard shapes run standalone — word-set-only and corpus-only;
- a **forced** failure (a word set doing `1 0 /`, whose runtime-error text
  legitimately differs from CPython's) reds ONLY its shard, exits 1, and names
  the word set — while `#stringtest` passes in the same window.

Shard names change job keys, so this was landed while the matrix was GREEN
(`1413b872ee62`, full, all tiers), per the rule `CONFORMANCE_SHARDS` records:
no red could migrate and no phantom NEW-RED/FIXED pair is manufactured.

**Follow-ups filed** — the pole is now blocktest and it is T's tool no longer:
[[bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython]].

## Log
- 2026-08-11 — resolved, commit c488470af.
