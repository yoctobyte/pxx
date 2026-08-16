---
summary: "Should plexus run with turbo disabled (or a fixed governor) so bench rows are comparable by construction? It costs ~13-24% throughput on everything the box does, not just the bench, so it is not Track T's call to make silently"
type: decide
track: U
prio: 0
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


## REJECTED 2026-08-14 by the user — not relevant at this point

> *"We know that there's boosting the clock, and we have a very quantized 24%
> speed, which totally aligns with the processor boost speed. It's really not
> relevant at this point."*

The phenomenon is understood and it is not costing anything. Pinning the clock
would trade ~13-24% of throughput on everything the box does — the watcher, the
builds, the human's own work — to buy comparability nobody is currently
consuming.

**Rejecting costs nothing, because the measurement already landed.** The
per-run TASK clock is recorded on every bench row
(`tstate/bench-clock.tsv`: `mhz`, `mhz_lo`, `mhz_hi`, `box_mhz`, sampled from
the CPU the child actually ran on). So the series stays analysable after the
fact rather than being made uniform up front — which was the real goal, and the
option this ticket's own recommendation preferred.

**When it becomes relevant again:** optimisation work that needs accurate,
comparable absolute numbers. At that point re-open — and note the data to decide
it with will already exist, because the clock column keeps accumulating whether
or not anyone is asking. Nothing has to be re-instrumented first.

Related and still open on its own terms:
[[bug-t-bench-slowdowns-are-quantized-by-cpu-p-state]] holds the analysis, and
is parked waiting for a few hundred plexus rows on the corrected task-clock
basis — that accumulation is unaffected by this rejection.

## 2026-08-16 — the revisit condition was tested, and it CONFIRMS the rejection

This ticket's own recommendation named the one thing that would reopen it:

> *"Revisit only if the recorded `mhz` column turns out **not** to separate the
> populations cleanly once a few hundred plexus rows have accumulated."*

Those rows have accumulated (270 on the corrected task-clock basis, 101 of them
long-workload). It separates them cleanly:

| | n | median task clock |
| --- | --- | --- |
| clean rows (< 1.20x their day's best) | 92 | 2542 MHz |
| inflated rows (>= 1.20x) | 9 | 2090 MHz |

Ratio between the two states 1.217; median inflation actually observed on those
rows 1.223 — agreement to **0.5%**, and `corr(ratio, task_mhz) = -0.317`. Eight
of the nine inflated rows are labelled by the clock alone; the ninth was an
instrument bug, now fixed (below). So the condition for reopening is not met,
and the rejection stands on measurement rather than on plausibility.

**Correction to this ticket's own measurement section.** It records that "2600
MHz was never observed" and that the two-point base/boost model does not
describe the box. That was the *box-mean* instrument plus unpinned spinners,
which migrate. The corrected per-task clock reaches **2576 MHz** — the datasheet
2.6 GHz boost — and the inflated rows sit at ~2090, the 2.1 GHz base. The
two-point model is right after all, so option B ("pin to base, well below where
real load sits") would cost more than this ticket estimated, not less.

**And one instrument bug this surfaced**, since it affects any future revisit:
`TaskClock` followed the pid testmgr spawns, which for the `selfcompile fpc` row
is the **`fpc` driver** — it forks `ppcx64` and then blocks in `wait()`, so the
sampler read an idle core at the governor's floor. Every row below 1700 MHz in
the whole file was that one workload, claiming 1285-1661 MHz against a 6333-6686
ms runtime band. Fixed (`testmgr._running_pid`); `bench-clock.tsv` carries a
MEASUREMENT BASIS CHANGED line. The clock column keeps accumulating, as this
ticket promised, and is now trustworthy for every workload.

## Reconfirmed 2026-08-16 by the user, and the recipe for when it IS relevant

> *"i think the decide bench box clock ticket was decided iirc — as not relevant
> until we need precise measurements when we start working on optimization
> tickets. but if it's easy fixed, sure."*

Recalled correctly; this is that decision, unchanged. Recorded here rather than
in a new ticket because a Track T agent re-filed it as a duplicate on 2026-08-16
having searched `decided/` and `done/` but **not `rejected/`** — worth noting for
the next agent, since a rejected `decide-` is exactly where a settled question
lives.

It *is* easy, checked on plexus: `sudo -n` is passwordless,
`intel_pstate/no_turbo` reads `0`, governor `schedutil` with `performance`
available. So when optimisation work needs comparable absolute numbers:

```sh
echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo   # pin to base
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo   # restore
```

Neither survives a reboot, which is the right default. **Pin for the RUN, not
for the box** — a standing pin taxes the watcher's full matrix continuously to
buy comparability only a handful of measurements consume. Keep recording the
clock either way: a row at boost on a supposedly pinned box is a silently
reverted sysfs write.
