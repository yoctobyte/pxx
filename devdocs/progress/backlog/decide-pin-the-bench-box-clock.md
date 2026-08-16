---
track: U
prio: 20
type: decide
blocked-by: []
summary: "Should plexus run with a PINNED CPU clock (no_turbo or the performance governor) so bench rows are comparable by construction? Root-only, and it changes the box for everything the user runs, not just the bench. Track T's recommendation after measuring: NO — the recorded per-task clock already labels every inflated row, so pinning buys comparability we now get for free and costs ~20% throughput."
---

# Decide: pin plexus' CPU clock for the bench series?

- **Type:** decide — **Track U** (the escalation lane)
- **Opened:** 2026-08-16
- **Filed by:** Track T, splitting the one non-measurable item out of
  [[bug-t-bench-slowdowns-are-quantized-by-cpu-p-state]] so that ticket can
  close. T does not make this call: `/sys/devices/system/cpu/intel_pstate/no_turbo`
  is root-only and pinning changes the machine's behaviour for **everything the
  user runs on it**, not just the benchmark. That is a shared-machine decision,
  not a tooling one.

## The fork

`schedutil` + turbo means a bench row can be taken at ~2.1 GHz (base) or
~2.58 GHz (boost), and which one you get depends on what else the box was doing.
Three ways to live with that; the third is the one needing a decision:

1. **Void rows by ratio.** REJECTED, for three independent reasons now — see the
   parent ticket. Briefly: no single threshold means the same thing for a tight
   loop and for selfcompile; a threshold cannot separate clock from exposure;
   and it cannot separate "the box was slow" from "the compiler got faster",
   which is how a real 3.6x raytracer optimization made 49 innocent rows look
   contended.
2. **Record the clock.** DONE, and it works — the measurement below.
3. **Pin the clock.** `no_turbo=1`, or the `performance` governor. Every
   measurement then happens in the same state and rows are comparable by
   construction. **This is the open question.**

## What the measurement says (2026-08-16, 101 long-workload plexus rows)

| | n | median task clock |
| --- | --- | --- |
| clean rows (< 1.20x their day's best) | 92 | 2542 MHz |
| inflated rows (>= 1.20x) | 9 | 2090 MHz |

Ratio between the two states **1.217**; median inflation actually observed on
those rows **1.223**. Agreement to 0.5%. Eight of the nine inflated rows are
labelled by the clock alone; the ninth was an instrument bug, since fixed.

So option 2 already delivers what option 3 would buy: an inflated row is
identifiable from the data, after the fact, at no cost.

## Track T's recommendation: do NOT pin

- The comparability argument is largely spent — the clock is recorded per row,
  so the series is analysable as it stands.
- Pinning to base costs roughly **20%** of the box's throughput on every
  workload, and this box also runs the watcher's full matrix, where wall-clock
  is the product (`meta-t-dev-throughput-and-track-a-t-integration`).
- It is a persistent, machine-wide change to a box the user keeps partly
  *because it is quiet and cheap to leave on*
  (`~/POWER_BUDGET.md`), and clock pinning interacts with both.

## If the answer is "pin it anyway"

Then keep the recorded clock as a cheap assertion that the pinning actually
held — a row at 2.58 GHz on a supposedly pinned box is a silently reverted
sysfs write, and that is worth catching. The parent ticket said the same.

## What unblocks

Answering this closes the last open item in
[[bug-t-bench-slowdowns-are-quantized-by-cpu-p-state]]. Nothing else waits on it;
a "no" is a no-op and a "yes" is a small sysfs/systemd change plus a
MEASUREMENT BASIS CHANGED line in `bench.tsv`.
