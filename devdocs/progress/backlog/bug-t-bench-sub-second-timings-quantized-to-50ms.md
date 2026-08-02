---
track: T
prio: 65
type: bug
blocked-by: []
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
