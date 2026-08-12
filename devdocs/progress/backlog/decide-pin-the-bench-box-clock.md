---
summary: "Should plexus run with turbo disabled (or a fixed governor) so bench rows are comparable by construction? It costs ~13-24% throughput on everything the box does, not just the bench, so it is not Track T's call to make silently"
type: decide
track: U
prio: 40
---

# Decide: pin plexus's CPU clock for the bench series?

- **Type:** decision (Track U) — **Track U**
- **Opened:** 2026-08-12, from
  [[bug-t-bench-slowdowns-are-quantized-by-cpu-p-state]] option 3.
- **Not blocking:** option 2 (record the clock per row) is done and landed, so
  the series is analysable either way. This decides whether to remove the
  variable instead of measuring it.

## The fork

Bench rows on plexus are taken at whatever clock the governor happened to pick.
Recorded rows now carry that clock (`tstate/bench-clock.tsv`), so a slow row is
identifiable after the fact. The question is whether to go further and make
every row comparable *by construction*.

**Option A — leave it alone (Track T's recommendation).** Turbo stays on, the
box keeps its full speed for everything, and comparability comes from the
recorded `mhz` column. Costs nothing; requires the analysis to filter.

**Option B — pin the clock.** `echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo`
(or a `performance` governor with a fixed max) so every measurement is taken in
the same state. Buys a directly comparable series with no filtering. Costs
throughput on *everything the box does* — this is the machine's global CPU
policy, not a bench setting — and needs root plus something to reapply it across
reboots.

## Why this is Track U and not Track T

Track T owns the tool, and the tool now measures the clock. Changing the
machine's power policy is a decision about the user's box: it makes every
compile, every gate and every agent on plexus slower, in exchange for a tidier
benchmark series. Track T should not make that trade on the user's behalf.

Worth weighing against [[xeon-quietness-matters]]-style considerations: `no_turbo`
lowers the ceiling, so it reduces heat and noise rather than adding any.

## What was measured (2026-08-12, watcher stopped)

The two-point base/boost model this inherits does **not** describe the box.
Driver is `intel_cpufreq` (intel_pstate **passive**) under `schedutil`:

| busy threads | max MHz observed |
| --- | --- |
| 1–4 | ~2095 |
| 6–12 | ~2395 |

2600 MHz was never observed, and the clock rises with more active cores — a
governor effect (per-CPU utilization), not a core-count turbo bin table. So
option B's "remove the variable" is a stronger claim here than it looks: it
would pin to base, well below where real multi-core load already sits.

## Recommendation

**Option A.** The measurement was the actual goal, it is landed, and it costs
nothing. Revisit only if the recorded `mhz` column turns out not to separate the
populations cleanly once a few hundred plexus rows have accumulated.
