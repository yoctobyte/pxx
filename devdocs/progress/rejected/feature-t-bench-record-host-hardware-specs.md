---
track: T
prio: 55
type: feature
blocked-by: []
status: rejected
---

# Benchmarks record the host *name*, but nothing about the hardware

`tstate/bench.tsv` carries a `host` column (`date host sha workload level ms`),
so a measurement can be attributed to a machine. What it cannot say is what
that machine *is*: `borg` and `xeon` are bare names, and neither `borg.json`
nor `xeon.json` records a CPU model, core count, clock, or memory.

That became load-bearing when the watcher moved to a slower box on 2026-07-31:

```
borg   11242 rows   2026-07-11 .. 2026-07-31
xeon     956 rows   2026-07-31 .. 2026-08-01
```

`mandelbrot -O2` reads 1317.2 ms on borg's last run and 1867.8 ms on xeon's
first. Nothing in the data explains the 40% jump, so anyone reading the series
— human or chart — sees what looks like a large regression on 2026-07-31.

## The specs, for now (read off the machines 2026-08-02)

| host | CPU | cores | RAM |
| --- | --- | --- | --- |
| `borg` | Intel Core i7-6700 @ 3.4 GHz (turbo 4.0) | 4C/8T, Skylake | 16 GB DDR4-2133 |
| `xeon` | Intel Xeon E5-2620 v2 @ 2.1 GHz (turbo 2.6) | 6C/12T, Ivy Bridge-EP | 64 GB DDR3-1333 ECC |

That makes the observed ~1.45 ratio legible: roughly 1.5× on clock before IPC
differences, against half the memory bandwidth. Recorded here so the knowledge
is not lost, but it is hand-gathered — the ask below is for the watcher to
collect it, not for someone to keep this table current.

## Ask

Record the host's hardware alongside its identity, once per host rather than
per row: CPU model string, physical/logical core count, nominal clock, RAM, and
ideally a fixed calibration figure (a small fixed workload timed at enrol) so
two hosts can be related numerically rather than by name.

`<host>.json` is the natural place — it is per host, already published, and
already read by consumers. Adding a `hardware` object there needs no change to
bench.tsv's row format.

A calibration number is the part that turns this from documentation into
something usable: with it, a consumer can normalise across a host change
instead of merely annotating one.

## Why it matters

- The published benchmark charts on pxxc.org draw a single line per workload.
  Until something distinguishes hosts, a hardware change is indistinguishable
  from a performance regression. (The website side of this is separate — it
  currently discards the host column it already receives.)
- Track O's optimisation work is judged on these numbers. A 40% step that is
  really a different machine is exactly the kind of thing that gets chased as a
  regression, or worse, masks a real one underneath it.
- Historic borg data stays valuable if it can be related to xeon; without
  specs it can only be discarded or misread.

Found while looking at the benchmark charts (Track D/W), filed to T as the
owner of the bench log and the watcher that writes it.

## Log
- 2026-08-02 — rejected as a DUPLICATE of [[feature-t-bench-hardware-provenance]]
  (filed 2026-07-31, prio 60), which describes the same defect with the
  measured borg-vs-xeon table. Both were open at once because the same gap was
  rediscovered a day apart from opposite ends — one from the chart, one from the
  row counts. The work is still WANTED: `bench.tsv` remains
  `# date host sha workload level ms` with no hardware column. Track it there.
