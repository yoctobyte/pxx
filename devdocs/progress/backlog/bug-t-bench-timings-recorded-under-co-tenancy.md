---
summary: "bench records timings with no check that the box is quiet, so an agent's builds inflate the series up to +24% — and it is logged as SLOW, which reads as a performance regression"
type: bug
track: T
prio: 60
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
