---
summary: "The bench series' slow rows on xeon/plexus are not a contention continuum — they are QUANTIZED at 1.238x, the E5-2620 v2's 2.6/2.1 GHz boost-to-base ratio, which makes a void row detectable from the number alone"
type: bug
track: T
prio: 55
---

# Bench slowdowns are quantized by CPU P-state, not smeared by contention

- **Type:** bug (measurement validity) — Track T (`tools/twatch.py`, `run_bench_idle`,
  `devdocs/progress/tstate/bench.tsv`)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Hypothesis from:** the user, from eyeballing the series — *"pretty 'discrete'
  25% peaks… its xeons run at 2.1GHz with a boost of 2.6GHz, which is almost
  perfectly 25%"*. Tested against the recorded data below; it holds.
- **Refines, does not replace:** [[bug-t-bench-timings-recorded-under-co-tenancy]]
  (done). That ticket established co-tenancy inflates rows up to +24%. This one
  says *why it lands at 24% specifically*, and what that buys us.

## The hardware, from our own metadata

`devdocs/progress/tstate/meta/hosts.json`:

```json
"cpu": "Intel(R) Xeon(R) CPU E5-2620 v2 @ 2.10GHz", "mhz_max": 2600,
"governor": "schedutil", "turbo": true, "renamed_from": "xeon"
```

`2600 / 2100 = 1.2381`. The governor is free-running with turbo enabled, which
is exactly the condition that lets a measurement land in either state.

## The measurement

Every post-`MEASUREMENT-BASIS-CHANGED` row, restricted to workloads with >=8
samples and >=1s runtime (sub-second rows are clock artefact — see
[[bug-t-bench-sub-second-timings-quantized-to-50ms]]), each normalised to its
own workload's fastest observed time:

| host | n | <1.10 | **[1.10, 1.20)** | >=1.20 |
| --- | --- | --- | --- | --- |
| xeon | 798 | 92.7% | **0.6%** | 6.6% |
| plexus | 121 | 100.0% | 0.0% | 0.0% |
| borg | 3251 | 18.4% | **26.4%** | 55.2% |

xeon's high mode: min 1.221, **median 1.242**, max 1.345.
Predicted by the clock ratio: **1.238**. Agreement to 0.3%.

**The gap is the finding, not the magnitude.** Five samples out of 798 fall
between 1.10 and 1.20. A co-tenant taking a variable share of CPU produces a
continuum; a CPU stepping between two P-states produces a hole. borg fills the
band (26.4%) and is therefore a *different* phenomenon — do not apply this
explanation there.

The high-mode rows arrive in batches (11 in the 2026-08-03T18:38Z batch, 6 in
2026-08-04T05:06Z — the batch the co-tenancy ticket blamed), consistent with
"the box was busy during that window, so the package sat near base clock".

## Why this is worth acting on

It converts a statistical nuisance into a **detector**. A row that is >=1.20x
its own workload's best was almost certainly not taken at boost, and that is
knowable from the number alone — no load sampler, no `foreign_runs()`, no
process detection. It therefore catches the case the co-tenancy ticket flagged
as the hard one: a bare `make compiler/pascal26`, which is not a testmgr process
and which `foreign_runs()` cannot see.

## The workloads split into two families, and only one is purely clock-bound

Prompted by the user's follow-up — *"remarkable that speed is linear with CPU
speed, as if memory latency and transport is irrelevant here"*. Per-workload
median of the high-mode ratio:

| workload | level | n_all | n_hi | best ms | high-mode median |
| --- | --- | --- | --- | --- | --- |
| mandelbrot-p | -O2 | 85 | 4 | 1838.4 | 1.235 |
| raytracer | -O3 | 85 | 4 | 9256.0 | 1.237 |
| raytracer | -O2 | 85 | 6 | 10606.8 | 1.237 |
| mandelbrot-p | -O0 | 85 | 4 | 1831.4 | 1.239 |
| raytracer | -O0 | 85 | 3 | 17371.9 | 1.240 |
| mandelbrot | -O2 | 85 | 5 | 1857.7 | 1.248 |
| mandelbrot | -O0 | 85 | 5 | 1848.1 | 1.255 |
| **selfcompile** | **fpc** | 80 | 7 | 5677.8 | **1.274** |
| **selfcompile** | **-O0** | 85 | 5 | 11839.3 | **1.292** |
| **selfcompile** | **-O2** | 85 | 5 | 9233.5 | **1.298** |
| **selfcompile** | **-O3** | 85 | 5 | 9333.6 | **1.301** |

Two families, and **every selfcompile row sits above every tight-loop row**:

| family | workloads | median | vs clock ratio 1.238 |
| --- | --- | --- | --- |
| tight loops (mandelbrot, raytracer) | 7 | **1.239** | +0.1% — indistinguishable |
| selfcompile | 4 | **1.295** | **+4.6% MORE than clock alone** |

**The user's observation is right, for the tight loops.** mandelbrot and
raytracer track the core clock to within a tenth of a percent — they are
compute-bound on small working sets, and DRAM latency genuinely is irrelevant to
them. A 1.24 on those rows is a P-state artefact and nothing else.

**selfcompile is not purely clock-bound.** It loses ~4.6 points *more* than the
core clock can explain, which core frequency cannot account for. Candidates, in
no particular order and none of them measured yet: process spawn and file I/O
contending with the co-tenant; the uncore/memory clock dropping alongside the
core clock; a working set (the compiler is ~6.3 MB of code and ~160 MB bss) big
enough to be cache- and DRAM-sensitive in a way a mandelbrot kernel is not.

Note `selfcompile fpc` is in that family at 1.274 and involves **no pxx at
all**, so this is a property of the workload *shape* — compile-like: spawn, I/O,
large working set — not of our compiler.

### Two consequences

1. **The suite is not blind to memory behaviour.** A worry the "linear with
   clock" observation raises is that a benchmark set which only measures ALU
   throughput would never catch a regression in cache locality or allocator
   behaviour. The split says selfcompile carries that sensitivity even though
   the tight loops do not — so the suite has the coverage, concentrated in one
   family. Worth knowing which rows to watch for which kind of regression.
2. **The void threshold is one number but its meaning is not.** ~1.20 still
   separates clean from contended for every workload here. But "1.24 means a
   P-state drop" is only sound for the tight loops; on selfcompile the same
   contention shows up nearer 1.30, and a selfcompile row at exactly 1.24 is
   ambiguous. Do not build a detector that assumes a single expected inflation.

## Fix shape, cheapest first

1. **Void by ratio (no new plumbing).** When a row exceeds ~1.20x the workload's
   rolling best, mark it `contended` rather than entering it as data. One
   caveat: this cannot distinguish a P-state drop from a genuine 24% regression,
   so it must *report* the voided row, never silently drop it. A real 24%
   regression would show up as *every* row voided, persistently — a distinctive
   and loud signature.
2. **Record the frequency (direct measurement — preferred).** Sample
   `/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq` at the start and end
   of each workload, like the co-tenancy ticket's load check, and write it as a
   `mhz` column in `bench.tsv`. Then a void row is a *fact* rather than an
   inference, and the series becomes analysable after the fact. This is the
   option most in keeping with the repo's measure-don't-reason rule.
3. **Remove the variable.** Pin the bench box to a fixed clock — disable turbo
   (`/sys/devices/system/cpu/intel_pstate/no_turbo`) or set the `performance`
   governor — so every measurement is taken in the same state. Costs ~24% of
   absolute throughput and buys a comparable series. For a series whose only
   job is detecting regressions, comparability beats peak numbers, and this
   makes options 1 and 2 unnecessary.

Option 3 plus option 2's `mhz` column (as a cheap assertion that the pinning
actually held) is probably the right end state.

## The turbo mechanics are unknown and should be MEASURED, not looked up

Open question from the user: what actually drives the throttle on this part —
core temperature, active-core count, power limit — and can the package hand the
top bin from core to core in succession?

For E5-2620 v2 (Ivy Bridge-EP) the turbo bin is generally a function of active
core count, capped by package power and temperature, but **the exact bin table
for this specific chip should be measured rather than quoted from a datasheet
from memory.** It is directly observable and takes minutes:

```sh
# bin table by active-core count, on the box itself
for n in 1 2 3 4 6 12; do
  for i in $(seq $n); do (while :; do :; done) & done
  sleep 5
  echo -n "$n busy: "; grep "cpu MHz" /proc/cpuinfo | awk '{s+=$4} END {print s/NR" MHz avg"}'
  kill %$(jobs -p | wc -l) 2>/dev/null; kill $(jobs -p) 2>/dev/null; wait 2>/dev/null
done
```

Sampling `/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq` per-core during
a real bench run answers the migration question at the same time. This is worth
doing once and recording in `hosts.json` alongside `mhz_max`, since every
inference in this ticket currently rests on a two-point base/boost model that
the hardware may not actually implement.

## The dev box is worse, not better

`i7-6700`, read from the box: `base_frequency` 3.4 GHz, `cpuinfo_max_freq`
4.0 GHz (**17.6%** headroom), `cpuinfo_min_freq` **800 MHz**, governor
`powersave`, turbo enabled. So a casual benchmark run on a dev machine has a
**5x** frequency range available to it rather than the Xeon's 1.24x. Any timing
taken there is uninterpretable unless the clock is pinned or recorded.

## Open

**plexus shows zero high-mode samples in 121 rows.** That is either the
co-tenancy fix working, or too few samples to have caught a busy window yet —
121 rows against xeon's 798, and xeon's high mode is only 6.6% of samples, so
~8 would be expected. Not yet distinguishable. Re-check once plexus has a few
hundred long-workload rows; if it stays clean, say so in the ticket rather than
assuming.

**borg is unexplained and is not this.** Its 26.4% in the gap band and 55.2%
above 1.20 (with a large pile past 1.40) say continuous variation, not a
two-state clock. Worth its own look; different host, possibly different CPU,
possibly genuinely contended or thermally limited.

## Gate

Track T: `tools/testmgr.py --tier full` green for tooling changes. The real
proof is behavioural — after the fix, re-run the analysis above and the >=1.20
population should be empty (option 3) or fully labelled (options 1/2).
