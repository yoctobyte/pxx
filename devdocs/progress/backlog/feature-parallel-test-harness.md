---
prio: 45
---
# Parallel test harness — OS-level, opt-in, safe on weak hardware

- **Type:** feature (test infra). Track A (Makefile/tools; no compiler changes).
- **Opened:** 2026-07-07, from a design discussion.

## Idea
The gate is embarrassingly parallel at the ORCHESTRATION level: cross-target
builds (x86-64/i386/aarch64/arm32/riscv32/xtensa) are independent pascal26
invocations; conformance tests, lua scripts, and bXXX regressions are
independent compile+run pairs. Parallelize with make -j / xargs -P — zero
compiler changes, the compiler binary stays single-threaded and deterministic.

## Requirements (user-set)
1. **Opt-in/out:** e.g. `make test PAR=8` or auto `-j$(nproc)` with `PAR=1`
   forcing today's serial behavior. Default conservative (serial or nproc/2)
   so nothing changes for existing workflows.
2. **Halt detection:** every parallel job wrapped in `timeout` with a
   per-class budget; a hung compile fails that job with a clear message
   instead of wedging the whole gate.
3. **Weak hardware:** budgets scaled, not absolute — a 15-year-old laptop or
   a Pi 1 must not get false timeouts. Calibrate: time one known-cost compile
   at gate start and scale per-job timeouts from that baseline. Memory:
   parallel pascal26 instances each map a large BSS; cap concurrency by
   available RAM (e.g. min(nproc, mem/1GB)).
4. **Deterministic reporting:** collect per-job logs, print in fixed order at
   the end so output diffs stay stable; first failure quoted verbatim.

## Non-goals
Threading inside the compiler (parked — global-state refactor, self-host
byte-identical gate risk, poor cost/benefit while self-build is ~7s).

## Also
- Benchmark refresh belongs nearby: FPC comparison is stale, and once
  pxx-built tcc self-compiles, `tcc-by-pxx vs tcc-by-gcc self-compile time`
  becomes the first real cross-compiler benchmark. Consider a
  `make benchmark-tcc` target when the tcc corpus arc lands.

## Gate
`make test PAR=N` green and equal in verdict to serial run on the same tree;
serial path byte-identical to today; one injected hang (sleep-loop test)
fails cleanly with the timeout message.
