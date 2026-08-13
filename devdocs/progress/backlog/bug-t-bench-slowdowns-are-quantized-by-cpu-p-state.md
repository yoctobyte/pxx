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

## MEASURED on plexus, 2026-08-12 — and it does not match the two-point model

Watcher stopped, box otherwise quiet, N unpinned busy-loops, `scaling_cur_freq`
across all 12 CPUs after 6s:

| busy threads | max MHz | mean MHz |
| --- | --- | --- |
| 1 | 2096 | 2095 |
| 2 | 2095 | 1797 |
| 3 | 2095 | 1871 |
| 4 | 2098 | 2095 |
| 6 | **2395** | 2394 |
| 12 | **2394** | 2394 |

**2600 was never observed, and the clock goes UP with more active cores** —
the opposite of a core-count turbo bin table. The mechanism is the governor,
not the silicon: `scaling_driver` is `intel_cpufreq` (intel_pstate in **passive**
mode, `status=passive`) driven by `schedutil`, which picks a P-state per CPU
from *that CPU's* utilization. An unpinned single spinner migrates, so no one
CPU sustains high utilization and nothing ramps; six do. `no_turbo=0`,
`max_perf_pct=100`, `min_perf_pct=46`, `turbo_pct=34`, `num_pstates=15`.

Under the watcher's own compile load, turbostat reports ~2394 MHz busy.

So the two-state base/boost story is too simple for this box: 2395 is a middle
bin the model does not have, and it is where real load actually lands. This
does **not** refute the 1.238 finding in the recorded data — the ratio and the
void in the histogram are facts about 798 rows — but it does mean the *causal*
explanation ("boost vs base") should not be treated as settled. The `mhz`
column below is what settles it, per row, from here on.

Also note **borg is now retired as a tstate host** (2026-08-12; it is a dev
station and Track T moved to plexus). Its 3251 rows keep their historical value
but no new borg rows will arrive, so the "borg is unexplained and is not this"
thread is closed by attrition rather than answered.

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

## DONE 2026-08-12: option 2 (record the frequency)

`bench_time()` now samples `scaling_cur_freq` around every clean run and returns
the clock **of the run that produced the reported time** — the reported number is
a min, so a batch average would describe a different run than the one recorded.
`testmgr --bench` writes `date host workload level mhz mhz_lo mhz_hi` and the
watcher publishes it; a row taken below 97% of `cpuinfo_max_freq` also says so on
the console at the time.

It went to a **SIDE FILE** (`tstate/bench-clock.tsv`), not a new bench.tsv column,
for the reason `record_host_epoch()` already documented: bench.tsv is indexed
positionally and columns 6/7 are `uforth_sha`/`rss_kb` on the cross-runtime rows,
so a new column at 6 would silently reinterpret every uforth row. Join on
(date, host, workload, level) — `date` is one timestamp per batch, so it is exact.

Verified live: one 3-run batch recorded 1977 / 2394 / 2394 MHz, i.e. **the same
workload measured at two different clocks inside a single batch**, which is the
phenomenon this ticket is about, now visible in the data instead of inferred
from it.

Option 1 (void by ratio) is deliberately NOT implemented: the ticket's own
analysis shows a single threshold cannot mean the same thing for tight loops
(1.239) and selfcompile (1.295), and with a measured clock the inference is
unnecessary.

## Still open: option 3 (pin the clock) — needs a human decision

`intel_pstate/no_turbo` is writable only as root, and pinning changes the box's
behaviour for everything the user runs on it, not just the bench. It is
therefore a Track U call, not something Track T should do silently to a shared
machine. Recommendation: leave turbo on and rely on the recorded `mhz` — the
measurement makes the series analysable after the fact, which was the actual
goal, and it costs no throughput.

## Gate

Track T: `tools/testmgr.py --tier full` green for tooling changes. The real
proof is behavioural — once a few hundred plexus rows carry `mhz`, re-run the
analysis above and check the >=1.20 population is fully labelled.

## 2026-08-13 — the `mhz` column was measuring the wrong thing, and is fixed

Re-running the analysis the Gate asks for surfaced a defect in the instrument
this ticket added on 08-12. `cpu_mhz()` returns the **mean across all online
CPUs**, and a bench workload is single-threaded: eleven of plexus' twelve CPUs
sit at the ~1196 MHz floor (`min_perf_pct=46`) while the twelfth runs the
benchmark. One core at 2394 and eleven at 1196 averages 1296 — and every row the
column produced fell in **1283-1911 MHz on a box whose busy clock is 2394**.

So the column recorded **occupancy, not speed**, and could not answer the
question it was added for. Worth stating plainly because the number looked
perfectly reasonable: low clocks on a contended box is exactly what one expects
to see, which is why nothing flagged it for a day.

**Fixed:** `TaskClock` samples, every 250 ms while the child runs, the clock of
the CPU the child is *actually on* (`/proc/<pid>/stat` field 39 -> that CPU's
`scaling_cur_freq`). Sampled rather than read once because schedutil both
migrates the task and ramps the P-state during a run. The old box-wide mean is
kept as a new **`box_mhz`** column — appended, never inserted, per this file's
own positional-join rule — because it turns out to be a fair contention proxy,
which is a different useful thing. `bench-clock.tsv` carries a MEASUREMENT BASIS
CHANGED line in the style bench.tsv already uses; do not compare across it.

Immediate confirmation, a 3 s single-threaded spinner on a busy box:

```
task_mhz = 2081     <- the core it ran on
box_mhz  = 1884     <- mean across all 12 CPUs
```

### And the deschedule guard cannot see this, by construction

`bench_time` discards a run when `wall > cpu * 1.06`. That catches an
**interrupted** run, never a **slow** one: at a low P-state the task keeps its
core and burns proportionally more CPU time, so `wall/cpu` stays ~1.0 while the
run takes 40% longer. Measured above: `wall=3.03s cpu=3.03s`. This is precisely
why the clock has to be recorded rather than inferred from that ratio — noted in
the code so the guard is not mistaken for coverage it does not provide.

## The two mechanisms separate, and the 1.238 prediction holds

A full bench under a running full tier (diverted to a scratch tsv — the tracked
series must not carry rows taken under a load I created), against each
workload's prior best:

| workload | best | inflation | task_mhz |
|---|---|---|---|
| raytracer-p fpc | 0.042 s | 1.202 | 2032 |
| sieve -O0 | 0.115 s | 1.215 | 2087 |
| fib -O2 | 0.221 s | 1.228 | 2079 |
| raytracer-p -O0 | 0.428 s | 1.233 | 2095 |
| nbody -O0 | 0.907 s | 1.234 | 2095 |
| mandelbrot-p -O2 | 1.836 s | 1.237 | 2091 |
| **raytracer -O3** | **9.218 s** | **1.758** | 2094 |
| **selfcompile -O0** | **12.205 s** | **1.895** | 2092 |

Task clock is uniform at ~2090 across every row, so it cannot be what separates
them. Two distinct effects, and the corrected instrument is what makes them
separable:

1. **A clock floor of ~1.237 on everything.** The short workloads cluster at
   1.202-1.237 — median **1.237** against this ticket's predicted **1.238**,
   agreement to 0.1%. That is what you would see if the reference rows were
   taken near 2600 and today's at 2095 (2600/2095 = 1.241). The reference rows
   predate the clock column, so this stays an **inference** until enough rows
   carry a task clock on both sides — but it is the same 1.238 the 798-row
   histogram found, arrived at independently.
2. **A contention penalty that grows with duration**, on top: 1.24 -> 1.76 ->
   1.90 as the workload goes 1.8 s -> 9.2 s -> 12.2 s, at identical clock. The
   likely mechanism is the sampling strategy itself — `bench_time` reports
   min-of-N, which dodges busy windows only for runs short enough to fit between
   them. A 12 s run cannot dodge anything, so even its best sample is
   contaminated. Stated as a hypothesis: it fits, and it is not yet measured.

**Consequence for the fix shape above: option 1 (void by ratio) stays rejected,
and for a second reason now.** A single threshold cannot separate these two
effects, because they add — a 1.24 row is clock, a 1.90 row is clock plus
exposure, and no threshold on the ratio alone tells you which. The recorded
clock does.

## Still open (unchanged)

The behavioural proof this ticket's Gate asks for still needs a few hundred
plexus rows carrying a task clock — the 30 rows above are one batch, all taken
under a load I created, which is the right way to see contention and the wrong
way to characterise a series. The old-basis rows cannot contribute. Re-run the
analysis once the watcher's own idle benches have accumulated.
