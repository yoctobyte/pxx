---
prio: 20
track: B
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
