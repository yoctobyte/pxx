---
summary: "bench.tsv records a hostname but no hardware — the series silently changed machines today"
type: feature
track: T
prio: 60
status: done
owner: claude@xeon
---

# Benchmarks need hardware provenance, not just a hostname

- **Type:** feature (Track T tooling) — filed by `claude@borg` 2026-07-31
- **Lane:** Track T owns `tools/testmgr.py` / `tools/twatch*` / `bench.tsv`;
  xeon holds T, so this is xeon's to implement.

## The problem, and it is live right now

`bench.tsv` is `# date host sha workload level ms` — it records **which host**
but nothing about **what that host is**. A hostname is not a hardware identity:
the same name survives a CPU swap, a RAM upgrade, a governor change or a kernel
update, and the numbers silently stop being comparable.

That stopped being hypothetical today. Every benchmark row before 2026-07-31 is
**borg, i7-6700 @3.4GHz**. From today the job moved to **xeon, E5-2620 v2
@2.1GHz (2.6 turbo)**, measured **40-90% slower on identical work**:

| workload | borg | xeon |
|---|---|---|
| `fib -O3` | 114.2 ms | 214.6 ms |
| `mandelbrot -O3` | 665.2 ms | 1016.0 ms |
| `mandelbrot-p fpc` | 364.4 ms | 515.1 ms |

Anyone reading the trend across today sees a ~2x performance regression that
did not happen. (`twatch_web` no longer *mixes* the two — fixed in `b5b50be85`,
tables are per-host — but it still cannot tell you *why* they differ, or notice
if borg's own hardware changes underneath its own name.)

## Do NOT reuse `scale` for this

testmgr already computes a per-box `scale` (a probe compile at startup,
`scale: 1.0` published in every report) and uses it to stretch timeouts on slow
boxes. It is tempting as a normaliser. **It is not valid for benchmarks:** it
read `1.0` on *both* borg and xeon despite the 40-90% gap above, because it is
calibrated on a compile (memory/IO-bound) rather than on compute. Use it for
timeouts, as intended; do not divide benchmark numbers by it.

## Proposed shape

**`tstate/hosts.json`** — host → list of hardware *epochs*, appended to whenever
the fingerprint changes:

```json
{"xeon": [{"fp": "a1b2c3d4e5f6",
           "from": "2026-07-31T16:56:10Z",
           "cpu": "Intel(R) Xeon(R) CPU E5-2620 v2 @ 2.10GHz",
           "sockets": 1, "cores": 6, "threads": 12,
           "mhz_max": 2600, "mem_total_kb": 62914560,
           "kernel": "7.0.0-28-generic", "gcc": "15.2.0",
           "governor": "performance", "turbo": true}]}
```

- `fp` = short hash over the identity-bearing fields. New fingerprint ⇒ append a
  new epoch with `from`; the previous one gets a `to`. History stays readable
  instead of being rewritten.
- Written by the watcher at run start — cheap, and it is the only process that
  knows a run is starting.
- **Prefer the side file over widening `bench.tsv`.** `read_bench()` indexes
  columns positionally (6 = `uforth_sha`, 7 = `rss_kb`), so inserting a column
  breaks the uforth rows. A `(host, date)` lookup into the epochs needs no
  schema change at all. If a column is wanted anyway, append `fp` at index 8.

Then in `twatch_web`: label each per-host bench table with its epoch (CPU +
governor at minimum), and mark the boundary when an epoch change falls inside
the displayed history — so a step in the series is visibly "new hardware here",
not a regression.

## Also worth capturing

- **Governor and turbo state.** On this Xeon that is the difference between
  2.1 and 2.6 GHz — a governor flip alone moves numbers more than most
  optimisation work does.
- **Load at bench start.** `idle_bench` runs benchmarks when the box is idle,
  which is right, but nothing records that it *was* idle. A one-line
  `loadavg` snapshot per bench run makes a contaminated series identifiable
  after the fact instead of merely suspicious.

## Why it matters beyond tidiness

Track O's entire case rests on these numbers. An optimisation campaign that
cannot distinguish "we got 15% faster" from "we changed boxes" cannot report
progress honestly — and this is the project that keeps a
[claims-discipline table](../../../CLAUDE.md) precisely because a plausible
wrong number is more expensive than a missing one.

## Log
- 2026-08-04 (`claude@xeon`) — implemented in the shape proposed, side file and
  all.

  `tstate/hosts.json` holds host -> hardware EPOCHS. `host_hardware()` reads
  cpu model / sockets / cores / threads / max MHz / MemTotal / kernel / gcc /
  governor / turbo from `/proc` and sysfs (no `lscpu` dependency), and the
  fingerprint is a 12-char hash over all of it. On this box it reads:
  `Intel(R) Xeon(R) CPU E5-2620 v2 @ 2.10GHz · 12t · schedutil · turbo`,
  2600 MHz max — which matches the ticket's own numbers.

  Governor and turbo are INSIDE the fingerprint, per the ticket's argument: 2.1
  vs 2.6 GHz on this box is more than most optimisation work moves. A devtest
  pins that specifically, because it is the field most likely to be dropped as
  "not really hardware".

  Epochs append, never rewrite: a changed fingerprint closes the previous entry
  with `to` and opens a new one with `from`, so the old numbers keep their
  context. Written from `publish()` (so a host that never benches still has an
  identity on record) and again at bench start, riding the same commit as the
  rows it describes. The unchanged case — every publish, all day — writes
  nothing.

  `bench.tsv` is untouched, exactly as the ticket asks: `read_bench()` indexes
  columns positionally (6 = uforth_sha, 7 = rss_kb), so a (host, date) lookup
  into the epochs is the change that costs nothing.

  `twatch_web` labels each per-host bench table with its current hardware and,
  when the history spans a change, prints a warn line naming what it was
  before. Verified against a fixture of the real borg -> xeon transition:

  > Intel(R) Xeon(R) CPU E5-2620 v2 @ 2.10GHz · 12t · schedutil · turbo
  > **hardware changed 2026-07-31T16:56:10 — rows before that are NOT
  > comparable with rows after (was: Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz)**

  The "load at bench start" ask is served better than proposed: `last_bench`
  now records `probe_ratio`, the speed-probe reading the batch was measured
  under (see [[bug-t-bench-timings-recorded-under-co-tenancy]]), plus `hw_fp`
  so a run is stamped with the epoch it belongs to. loadavg would have been the
  wrong instrument — measured the same day, it read 17.22 on a QUIET box, being
  a 1-minute decaying average.

  `scale` stays out of it, per the ticket's warning: it read 1.0 on both boxes
  despite the 40-90% gap, and it is for timeouts.

- 2026-08-04 — resolved, commit fbaed24cc.
