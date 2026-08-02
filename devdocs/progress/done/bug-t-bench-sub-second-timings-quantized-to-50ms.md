---
track: T
prio: 65
type: bug
blocked-by: []
status: done
owner: claude@xeon
---

# Benchmark timings under 1s are quantized to a 50 ms grid

Every sub-second measurement in `tstate/bench.tsv` lands on a ~50 ms grid
(offset ≈14 ms): 32, 64, 114, 164, 214, 264, 314, 364 … Longer measurements do
not. Measured over the whole log (12258 rows):

| range | rows | distinct values | on the 50 ms grid |
| --- | --- | --- | --- |
| 0–1000 ms | 7436 | 348 | **90.0%** |
| 1000–5000 ms | 2338 | 685 | 0.0% |
| >5000 ms | 2484 | 1845 | 0.4% |

348 distinct values across 7436 rows is the tell: the clock, not the workload,
is deciding the number.

## Why it matters

**61% of all benchmark rows are sub-second**, so most of the log has ±25 ms of
quantization error. On a 64 ms measurement that is ±39%. Any optimisation
smaller than the grid step is invisible on those workloads, and any *apparent*
change is one bucket of clock noise.

It also corrupts cross-host comparison. Deriving a borg→xeon scale factor per
workload gives:

```
raytracer   -O0   12892.6 -> 17450.4   1.354     <- long, credible
selfcompile -O2    6277.6 ->  9234.1   1.471     <- long, credible
mandelbrot  -O2     1366.2 ->  1867.8   1.367    <- long, credible
nbody        fpc      64.0 ->   164.3   2.567    <- two grid buckets, noise
sieve        fpc      31.9 ->    64.3   2.016    <- one grid bucket, noise
raytracer-p  fpc      63.9 ->    64.1   1.003    <- same bucket, noise
```

The long workloads agree within ~1.35–1.53. The short ones scatter from 1.00 to
2.57 and are pure quantization. Anything computed over all workloads inherits
that scatter — the naive median across all 30 pairs is 1.448 with a stdev of
0.267, most of which is not real.

## Ask

Time short workloads with a monotonic high-resolution clock, or run them to a
minimum duration (iterate until ≥1 s, divide) so the reported figure is not a
clock artefact. Either fixes it; the second also improves repeatability.

Worth checking whether the 50 ms figure points at a specific coarse timer in the
harness — the ~14 ms offset suggests a fixed startup cost added to a quantized
measurement rather than rounding of the total.

## Notes

Found while deriving host scale factors for the benchmark charts (Track W), not
by a failing test — the gate has no assertion about measurement resolution.

Related: `feature-t-bench-record-host-hardware-specs` (bench.tsv names the host
but records no hardware). Both are needed before cross-host benchmark numbers
mean anything; this one bounds what any calibration figure can achieve, since a
calibration workload timed on this grid inherits the same error.

## Log
- 2026-08-02 — fixed in `688a174aa`, gated by `tools/bench_timing_devtest.py`.
- **The ticket's own suspicion was right and its arithmetic was the clue.** The
  "~14 ms offset on a 50 ms grid" is not an offset: it is CPython's
  `Popen._wait()` poll schedule (0.5 ms, doubling, capped at 50 ms), whose
  cumulative wakeups are 31.5 / 63.5 / 113.5 / 163.5 / 213.5 ms. Passing
  `timeout=` to `subprocess.run` opts into that polling wait, so the harness
  timed the wakeup rather than the exit. No pxx code was involved — FPC-built
  binaries quantized identically, which is what ruled out our RTL.
- Direction matters and the ticket assumed the wrong one: the artefact reads
  LOW as often as high (same FPC sieve: 77.8-84.7 ms honestly, 64.1-64.5 ms
  through the old path). So historical sub-second rows are not merely coarse,
  they are wrong in both directions.
- `bench.tsv` carries a marker line under the header recording the basis
  change, so nobody derives a host scale factor across it. New rows will read
  LOWER than old ones for the same work, which cannot trip the `SLOW` check
  (it only fires on a >10% increase) but will look like an improvement that
  never happened.
- The cross-host scale factors this ticket was filed from should be re-derived
  once both hosts have post-fix rows; the long workloads (1.35-1.53) were
  already credible and should barely move.
- Out of scope, noted: the parallel job manager samples on `TICK = 0.5 s`, so
  per-job `elapsed` has the same shape at 500 ms granularity. Advisory numbers,
  not a published series — left alone deliberately.
- Follow-on now unblocked: `os.wait4` hands back `ru_maxrss`, which is exactly
  what [[feature-t-est-mem-from-measurement]] needs to replace testmgr's
  guessed `est_mem` table.

- 2026-08-02 — resolved, commit 688a174aa.
