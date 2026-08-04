---
summary: "bench records timings with no check that the box is quiet, so an agent's builds inflate the series up to +24% — and it is logged as SLOW, which reads as a performance regression"
type: bug
track: T
prio: 60
status: done
owner: claude@xeon
---

# Bench measures whatever the box was doing, and calls the result SLOW

- **Type:** bug (Track T — `tools/twatch.py`, `run_bench_idle`)
- **Found:** 2026-08-04 by `claude@xeon`, from the daemon's own log while working
  on this box. **The contaminating load was mine**, which is the point: a T
  agent working in a dev checkout while the watcher benches is normal operation,
  not misuse.

## What happened

The 2026-08-04T05:06Z batch at `9df2717684a3` came out uniformly slower and the
daemon logged every row as `SLOW (was ...)`:

```
bench selfcompile  -O0   15824.3ms  SLOW (was 12829.5ms)
bench selfcompile  fpc    7348.6ms  SLOW (was 5920.5ms)
```

Nothing regressed. I was building the compiler and running `gate.sh quick` in
`/home/neo/pxx` while the watcher benched in its own clone.

## The control that proves it

The suite times **FPC** as well as pxx. pxx is not involved in those rows at
all, so they cannot move for any compiler reason — and they moved with
everything else:

| | mean delta vs the previous batch |
|---|---|
| all 30 workloads | **+14.8%** |
| FPC-only rows (6) | **+14.8%** |
| worst row (`selfcompile fpc`) | **+24.1%** |

## The inflation is PER-ROW, not per-batch

Because a co-tenant's load is intermittent, whichever workloads happen to run
during it are hit and the rest are clean:

| workload | prev | now | delta |
|---|---|---|---|
| mandelbrot -O2 | 1879.3 | 1887.9 | +0.5% |
| mandelbrot-p -O3 | 981.6 | 981.0 | -0.1% |
| raytracer -O0 | 17581.9 | 17612.5 | +0.2% |
| raytracer -O2 | 10758.7 | 13125.4 | **+22.0%** |
| selfcompile -O0 | 12829.5 | 15824.3 | **+23.3%** |

So "discard the batch" is the only safe reading of a contended window — you
cannot tell from the numbers which rows were hit.

## Why this matters more than a noisy number

This series is what someone would consult to detect a real performance
regression, and **+24% is far larger than most real ones**. Worse, the
contamination announces itself as `SLOW`, i.e. in exactly the words a regression
would use. A reader who trusts it chases a compiler ghost; a reader who learns
not to trust it has lost the series.

It also silently becomes the new baseline: the next batch compares against these
inflated numbers, so the following run will look 20% FASTER — a phantom
improvement, which is the harder direction to notice.

## Fix shape

`testmgr` already learned to notice co-tenants for verdicts
([[bug-t-watcher-dev-contention-false-newred]]): `foreign_runs()` finds runs in
other clones, and a kill under co-tenancy is retried rather than believed.
Timings need the same awareness, but the response differs — a measurement taken
on a shared box is not retriable, it is void.

1. **Check before and after, not just before.** The load can arrive mid-batch,
   which is exactly what happened here. Sample at the start of each workload and
   again at its end; if the box was not quiet across the whole measurement, the
   row is void.
2. **Void, not merely flagged.** A row nobody can trust should not enter
   `bench.tsv` as data — write it with an explicit `contended` marker column, or
   skip it. Both beat a number that looks comparable and is not.
3. **`foreign_runs()` is not sufficient by itself.** The load here included a
   bare `make compiler/pascal26`, which is not a testmgr process. A load signal
   (`/proc/loadavg`, or the `idle_frac` sampler testmgr already keeps) catches
   what process detection misses.
4. **Do not suppress the SLOW annotation** — just make it say which it is.
   "SLOW under contention" and "SLOW on a quiet box" are different findings and
   only the second is worth a ticket.

Related, same design point from the other side:
[[feature-t-bench-idle-must-be-preemptible]] — bench currently blocks a new
push for 2-3 min. Bench wants the box to itself AND must yield it, so whatever
lands should settle both: bench only when quiet, and abandon the batch when the
quiet ends.

## Gate

A devtest over the void/keep decision (quiet -> keep; co-tenant at start, at
end, or in the middle -> void), plus `--tier quick` green. The contaminated
batch of 2026-08-04 is already marked in `bench.tsv`; it is the fixture this was
written from.

## Log
- 2026-08-04 (`claude@xeon`) — implemented as the user's call: **defer, and void
  the partial** (rather than flag rows or pin cores).

  - **Never starts** unless `/proc/loadavg` 1-min is under `BENCH_QUIET_LOAD`
    (2.0). Load rather than `foreign_runs()` because the load that spoiled the
    2026-08-04 batch included a bare `make compiler/pascal26`, which is no
    testmgr process at all.
  - **Sampled every 15s while running**, not just at the start — that batch was
    begun on a quiet box and the load ARRIVED mid-run, so a start-only check
    would have passed it. The during-limit leaves `BENCH_OWN_LOAD` (2.0) of
    headroom, or the batch would abandon itself on its own load.
  - **Abandon discards every row**, including the ones already collected: the
    contamination is per-row, so a partial batch is exactly as unreadable as a
    contended one. Void, never partial.
  - **Skips are counted** (`bench_skips`, consecutive, reset by a clean batch)
    and printed with the load that caused them, so "we have not benched in two
    days" cannot hide — the starvation this trades for trustworthiness has to
    be visible.

  Verified against real load on the box: at 0.64 it proceeds, at 5.04 (twenty
  spinners) it refuses to start and would abandon mid-batch.

  Not done, per the same call: no `contended` column and no core pinning.
  Flagging needs every reader to honour the flag — including twatch's own
  comparator, the thing that printed `SLOW (was ...)` in the first place — and
  a flag one reader ignores is worse than no row. Pinning was ruled out by the
  data: `mandelbrot` was untouched (+0.5%) while `selfcompile` took +23%, so
  the contended resource is memory bandwidth and cache, not core count.

  `tools/twatch_bench_quiet_devtest.py` pins the decision: idle starts, 9.1/15.4
  refused, mid-batch arrival abandons, our own load tolerated, push preempts,
  counter is consecutive, unreadable load degrades to running rather than never
  running.

- 2026-08-04 — resolved, commit 713269e96.
- 2026-08-04 (`claude@xeon`) — **gate replaced: speed probe, not loadavg**, after
  the user pointed out that one bench a day is the goal, the box has 12 cores
  and more work is planned for it, so the first cut was too strict.

  Measuring instead of guessing showed loadavg was wrong in BOTH directions:

  | busy cores | probe ratio | loadavg |
  |---|---|---|
  | 0 (quiet) | 1.00 | **17.22** |
  | 4 | 1.09-1.19 | 16.88 |
  | 12 | 1.65-2.17 | 17.62 |
  | 24 (a full gate) | 2.64-4.75 | 21.53 |

  loadavg is a 1-minute EXPONENTIAL AVERAGE, so it still read 17 on a box that
  had gone quiet a minute earlier, and it could not separate quiet from 12 busy
  cores. The shipped 2.0 threshold would have blocked benching for minutes
  after every burst — the starvation this ticket was supposed to make visible,
  caused by the fix itself — and could have waved a batch through at the start
  of a fresh burst.

  `speed_probe()` times a fixed in-process integer loop instead: the CPU
  actually available to a single thread right now, which is what the bench
  experiences. It deliberately does not compile anything — a compiler-based
  probe would slow down when the COMPILER regressed and switch benching off
  exactly when there was something worth measuring.

  The reference is this host's fastest-ever probe (`bench_probe_ref`), so there
  is no per-box constant and a new box calibrates itself; it relaxes 5% after 12
  consecutive skips so an unreachable reference — thermal throttling, a governor
  change, a Python upgrade — cannot switch benching off permanently.

  Tolerance **1.35**, deliberately generous per the user's call: 4 of 12 cores
  busy reads 1.05-1.19 and still benches, while 12 busy (1.65) and an
  oversubscribed gate (2.64-4.75) refuse. Verified end to end against real
  spinners, including that a recovered box benches IMMEDIATELY where loadavg
  would still have been reading ~20.

  Also: `box_speed` takes the min of 3 probes. A single probe's noise spans
  ~10%, the same order as the contention worth detecting — the first end-to-end
  run refused a 4-core-busy box at 1.19 purely on noise. Min, not mean: it is
  the least-interrupted sample rather than an average of interruptions.

