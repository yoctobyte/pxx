---
prio: 80  # raised 2026-07-07: full gate ~10min serial, run many times per session — biggest agent-throughput lever
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

## Scope tiers (user-set, 2026-07-07)
Parallelism is only half of it — CHOOSE what to test per iteration:
- `make test-quick` (exists) / **regressions-native**: bXXX + core at the
  native target only — the inner-loop tier while iterating on one bug.
- **limited**: + conformance + self-host fixedpoint, still native-only.
- **full**: everything incl. cross targets + corpus (lua/zlib/sqlite/tcc) —
  pre-push tier.
Tier selection explicit (`make test TIER=quick|limited|full`), never inferred,
so an agent states what it verified. BOARD/commit messages should name the
tier that gated the change.

## Design decision (user, 2026-07-07): a real MANAGER, in Python
Not a pile of Makefile -j hacks: one `tools/testmgr.py` that OWNS the run.
- Reads a declarative job list (job = compile cmd + run cmd + expected rc/
  output + tier tags + cost class). Start by GENERATING it from the existing
  Makefile targets rather than rewriting them, so serial `make test` stays
  the reference implementation and the manager is an alternative front end.
- ADAPTIVE scheduling: sample cpu load + available memory (/proc/stat,
  /proc/meminfo) each tick; launch more jobs while headroom, back off when
  tight. No fixed -j: a Pi 1 self-tunes to 1, a 32-core box saturates.
- Job classes with distinct budgets/weights: pascal26 compile (~1GB vm, cpu
  bound), tiny run (ms), qemu cross run (slow, cpu bound), corpus compile
  (lua/sqlite/tcc — long). The sampler decides WHICH class fits current
  headroom, not just how many.
- Safety: process-group per job (setsid) so kill is total; calibrated
  timeouts (scale from a probe job at startup); global deadline; memory
  watchdog kills newest job first on pressure; SIGINT = clean teardown of
  everything, no orphan qemu/pascal26.
- Deterministic report: fixed-order summary, per-job log files, first
  failure quoted; exit code = gate verdict. Tier selection as before
  (quick/limited/full).

## Resource governor (must-have, not nice-to-have)
Unmanaged -j WILL take the box down: each pascal26 maps a ~316MB BSS; add
qemu-user cross runners and 16 jobs swap-storm a 16GB machine. Rules:
- concurrency cap = min(nproc, free_mem / 1GB-ish per-job estimate), never
  more; single knob to force PAR=1.
- per-job `timeout` (calibrated at gate start — see weak-hardware note) AND a
  global gate deadline; on breach, kill the whole process group, not just the
  front process.
- jobs run `nice -n 10` so an interactive session stays responsive.
- fail-fast option for the inner loop (first red kills the run), keep-going
  for the full tier (collect all reds).

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

## Resolution (2026-07-07, fable-ac)
Landed `tools/testmgr.py` (Python 3, stdlib only):
- job list GENERATED from Makefile targets via `make -n` (serial make stays
  reference); recipe lines grouped compile+check, consecutive-compile groups
  atomic (golden comparisons); backslash-continued blocks kept whole; make's
  per-line exit semantics emulated exactly (no set -e across lines).
- adaptive scheduler: /proc/stat idle + /proc/meminfo MemAvailable per 0.5s
  tick; cap = min(nproc, mem-headroom/job); longest-expected jobs launch first.
- cost classes unit/qemu/selfhost/corpus/conformance; timeouts scaled by a
  startup probe compile; scale exported as TESTMGR_TIME_SCALE so scripts with
  inner `timeout` calls (conformance, sqlite) stretch on weak hardware too.
- safety: setsid per job + killpg (TERM window then KILL), memory watchdog
  (kills newest, requeues once), global deadline, SIGINT total teardown,
  xvfb exclusive-resource lock (two xvfb-run race on one display).
- tiers quick/limited/full; deterministic fixed-order report; exit = verdict.
- dissected wall-time poles: run_c_conformance.sh grew --shard I/N (6 shards);
  monolithic test-sqlite-threads split into per-arch subtargets calling
  tools/run_sqlite_thread_test.sh (serial aggregate target unchanged).

Proof: quick 11/11 in 3.6s; limited 691/691 in 3m40; full 1051/1051 GREEN in
5m13 vs >10min serial (serial reference run exceeded a 10-minute cap while
still mid-gate). Injected sleep-loop job killed by per-job timeout, no orphan
processes, SIGINT/deadline teardown verified.

## Log
- 2026-07-07 — resolved, commit bddb40c5.
