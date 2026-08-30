---
slug: bug-t-the-quiet-bench-has-produced-nothing-for-two-days-and-never-on-seven
title: "The idle bench refuses contended boxes, and our boxes are contended — so value numbers never accrue"
track: T
type: bug
prio: 65
status: backlog
found: 2026-08-30
found-by: frank-user, checking the owner's premise that quiet gating accumulates numbers on its own
summary: "bench.tsv has 17178 rows and NONE are from seven: 11242 borg, 3747 plexus, 2185 xeon — the first and last are retired hosts. plexus last benched 2026-08-28; seven's only attempt (2026-08-30T11:11) returned rc=1 rows=0. The contention guard is working exactly as designed and that IS the problem: it refuses to record a dirty measurement on a busy box, and our boxes are busy because sweeping is their job. Correctness numbers accrue for free from the sweeps; VALUE numbers do not accrue at all."
---

# The quiet bench has produced nothing for two days, and never once on seven

## The premise being checked

The owner's, and it is a good one: *"if O gating is quiet and just waits for
results, we will have numbers."* The machinery for that exists —
`idle_bench` in the watcher, `BENCH_LEVELS`, `bench.tsv`, 17178 rows. So the
question is only whether it is running.

## Measured

**Rows by host, whole archive:**

| host | rows | status |
| --- | ---: | --- |
| borg | 11242 | retired |
| plexus | 3747 | **last row 2026-08-28** |
| xeon | 2185 | retired |
| **seven** | **0** | never produced one |

`seven.json` → `last_bench: {date: 2026-08-30T11:11:19Z, rc: 1, rows: 0}`.
**The failure is recorded and nobody read it.** `plexus.json` → last bench
`2026-08-28T21:10`, two days ago.

So of the two live hosts, one has not benched in two days and the other has
never benched at all.

## Why, and the cause is a guard doing its job

`BENCH_QUIET_LOAD_FRAC = 0.60` — start only when per-core load1 is under 60%,
with a 10 s cap on waiting. `BENCH_CPU_WALL_MAX = 1.06` — discard any run whose
wall ran more than 6% ahead of its own child cpu time, because the process was
descheduled and the timing is contaminated. `BENCH_EXTRA_TRIES = 5` spare
attempts. Run out and you get `rc=1, rows=0`.

**Every one of those is the right call in isolation.** A discarded run is a spike
thrown away rather than averaged in, which is exactly the discipline that made
the DCE row trustworthy while the min-of-3 sweep's zeros were not.

**The trap is structural, not a bug in the guard:** the box with idle time is the
box that is sweeping, and sweeping is what fills the idle time. seven runs the
watcher at load 6-13 on 24 threads. The bench waits 10 s for quiet, does not get
it, burns its spare attempts on contaminated runs, and exits 1. **A correct
instrument, refusing to lie, producing nothing — and its refusal recorded in a
field nobody reads.**

## What this means for the promotion rule, precisely

Two different things were being conflated by "we will have numbers":

- **Correctness numbers accrue for free.** `full` and `opt` run anyway; a
  promotion's proof (self-host + all tests passed) arrives without anyone
  waiting. The owner's rule is unaffected.
- **Value numbers do not accrue at all.** *Does the pass still fire, does it
  still pay* is a bench question, the bench needs a quiet box, and no box is
  quiet. This is the same distinction as `optdiff` proving "not wrong" but never
  "works" — and it is where the missing half lives.

## What to do — three, and the third is the real one

1. **Read `rc` and `rows`.** `last_bench.rc == 1` or `rows == 0` should surface
   in `trackt.py health` / `twatch --status` like any other red. A silent
   instrument failure is the most expensive kind, and this one has been silent
   since the box was added.
2. **Give the bench a genuinely quiet window** rather than an idle slot it will
   never win: pause sweeping for its duration, or schedule it when the fleet is
   deliberately parked. It is minutes, not hours.
3. **Prefer flag-shaped answers to margin-shaped ones.** The transferable lesson
   from the same evening: the one row that survived a bad sweep survived because
   it was settled **by a flag, not by a margin** — decided by construction rather
   than a difference of means. Where a pass's effect can be made structural (does
   this call site emit the runtime call or not) the answer costs nothing and does
   not care about load. **Not every question can be reshaped this way, but the
   ones that can should be, because the boxes will never be quiet.**

## Also, under the new charter

`BENCH_LEVELS = ("-O0", "-O2", "-O3")`. The charter
(`decided/decide-the-o-level-charter`) now defines **`-O1` debug-safe** and
**`-O4` research**. `-O1` is a level users will actually select and should be
benched with the rest; `-O4` should not ride every run, matching its slower
sweep cadence. Not urgent — nothing benches today — but it is the same edit.
