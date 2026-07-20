---
prio: 20
track: B
blocked-by: [feature-os-targets-bsd-mac]
---

# Parallel load sampler — refinements (ramp/EMA, BSD/cgroup)

- **Type:** feature — optional polish on the shipped load-aware parallel-for.
  Track B (runtime, `lib/rtl/palparallel.pas`).
- **Opened:** 2026-07-17 (follow-up after
  [[feature-parallel-for-scheduling-policy]] landed functionally complete).

## Context

The load-aware worker modes (`pwLoadOnce`, `pwLoadCont`) ship and work: they
sample `/proc/stat` idle delta, cap to `capPct`, and (`pwLoadCont`) a monitor
thread re-tunes the active worker count mid-region. These are the OPTIONAL
refinements deferred from that feature — none are correctness issues (the sampler
fails safe to the fixed worker count; results are always exact).

## Items

1. **Ramp / hysteresis / EMA smoothing.** The `pwLoadCont` monitor currently sets
   `ActiveTarget := min(freeCores, cap)` directly. Under several competing
   load-aware jobs this can oscillate (each jumps to the free headroom, they
   collide, all back off, repeat). The original design was "take ~half the free
   headroom per poll and converge toward `capPct`": ramp
   `target += ceil((freeCores - active) * 0.5)`, and smooth the raw `/proc/stat`
   sample with an EMA to damp per-tick noise (the 50ms window is jittery).

2. **BSD sampler.** `/proc/stat` is Linux-only. On BSD read `sysctl kern.cp_time`
   (per-CPU jiffies) for the idle-delta; `sysctl hw.ncpu` for the core count.
   Gate behind the OS, degrade to the fixed count where absent. See
   [[feature-os-targets-bsd-mac]] (the sampler is called out there as part of the
   per-OS port, not just syscall numbers).

3. **cgroup-aware sampler.** `/proc/stat` shows HOST CPUs, ignoring a container's
   CPU quota, so `pwLoad*` over-parallelizes in a quota'd container. Read cgroup
   v2 `cpu.max` (quota/period) and `cpu.stat` to cap to the effective share.

4. **macOS sampler.** `host_processor_info` / `sysctlbyname` for load + `hw.ncpu`
   for count, if/when macOS hosting lands.

## Acceptance

- `pwLoadCont` holds a stable active count under sustained competing load (no
  visible oscillation) with the ramp + EMA.
- The sampler works (or degrades cleanly) on BSD and in a cgroup-limited
  container.
- No change to results or to the non-load-aware paths; native + cross stay green.

## Log
- 2026-07-17 — Filed as the optional-refinements follow-up; core load-aware
  feature is functionally complete (ramp/EMA, BSD, cgroup, macOS samplers).
- 2026-07-20 — **Items 1 and 3 landed** (Track B, `lib/rtl/palparallel.pas`).
  Items 2 (BSD) and 4 (macOS) stay open: neither OS is available to test on, and
  a sampler written blind is worse than none — it would fail in the direction of
  over-parallelizing. They should be picked up with
  [[feature-os-targets-bsd-mac]], not before.

  **1 — ramp + EMA.** `PXXQueryFreeCoresSmoothed` (alpha 1/4, 1/256-core fixed
  point) feeds the monitor; `PXXQueryFreeCores` is untouched so `pwLoadOnce`
  still sees a raw single sample. The monitor now moves half the gap per tick
  when GROWING, so two competing regions converge on a split instead of both
  claiming the whole headroom and oscillating. Shrinking is deliberately NOT
  ramped — when the sample says the CPU is gone, yielding it immediately is the
  polite behaviour.

  Measured on an 8-core host with background load, 12 ticks at 50 ms:
  `raw: 7 6 6 1 2 1 0 2 5 7 7 5` (5 jumps of >=2) vs
  `smoothed: 3 4 4 4 4 4 0 0 3 4 4 5` (2 jumps). Second run: 4 vs 1.

  **3 — cgroup v2 quota.** `PXXQueryCgroupCores` reads `/sys/fs/cgroup/cpu.max`
  and caps the core budget in both `ResolveWorkers` and the monitor. Rounds the
  quota UP (1.5 cores -> 2, not 1) and returns 0 for no-limit / not-in-a-cgroup /
  unreadable, which every caller reads as "do not cap". The parser is exported as
  `PXXParseCgroupCpuMax` because a host outside a cgroup cannot exercise the real
  file — verified against `max 100000`, exact/fractional/multi-core quotas, zero
  quota, zero period, empty, garbage, and an implausible ratio.

## Follow-up worth its own ticket: 0 is ambiguous

`PXXQueryFreeCores` returns 0 both for "no sample available" and for "the machine
is completely busy", and every caller maps `free <= 0` to *use the full worker
cap*. That is the right fail-safe for the first meaning and precisely backwards
for the second: on a saturated box, `ParPolite` — the mode whose entire purpose
is to be polite — takes maximum width. This is pre-existing behaviour and not
touched here, but it deserves a distinct sentinel (say -1 for "no reading", 0 for
"genuinely nothing free") so the two cases can diverge.

## Blocked (2026-07-20)

Items 1 and 3 landed. Items **2 (BSD sampler) and 4 (macOS sampler)** are the
whole remainder, and both are per-OS syscall work that cannot be written
responsibly without the OS to run it on — a load sampler guessed at fails in the
direction of over-parallelizing, silently. `blocked-by:
feature-os-targets-bsd-mac`, which is where the per-OS port belongs anyway (that
ticket already names the sampler as part of its scope).

