---
prio: 35
---

# riscv32 cross-target test coverage is thin vs i386/arm32/aarch64

- **Type:** bug (test coverage gap) — **Track A** (backend / cross-target gate).
  Filed by Track T from the tier-coverage dashboard; hand off to whoever holds A.
- **Status:** backlog
- **Opened:** 2026-07-11 (surfaced by the new dashboard tier-coverage panel,
  [[feature-testmgr-fpc-compare-and-web-dashboard]])
- **Owner:** —

## Why

The `full` tier genuinely runs the cross matrix (proven: i386 111 jobs, arm32
111, aarch64 103 — all pass via qemu), but **`test-riscv32` runs only ~19 jobs**
and they are almost all C cross-entry checks (`ccross_entry.c`, `ccross_args.c`,
`ccross_double_to_int.c` … → exit 42), NOT the fuller Pascal battery the other
arches get. Compare the Makefile targets:

- `test-i386` / `test-arm32` / `test-aarch64`: `hello.pas`, `test_inline_expand`
  with `-O0`-vs-`-O2` output parity, and the broader shared suite.
- `test-riscv32` (Makefile ~2797): a handful of `ccross_*.c` programs only.

So the riscv32 backend is materially less exercised — a Pascal-side codegen
regression on riscv32 (calling convention, spills, float, inline parity) would
sail through `full` GREEN. The dashboard now flags this family **⚠ thin**
(< 1/4 of peer job count).

## What

Bring `test-riscv32` up toward parity with `test-i386`: run the same shared
Pascal cross programs (`hello.pas`, `test_inline_expand` `-O0`==`-O2`, and
whatever the i386/arm targets iterate) through `--target=riscv32` +
`tools/run_target.sh riscv32`. Where a program genuinely can't run on riscv32
(missing syscall shim, unsupported feature), skip it explicitly with a reason
rather than omitting silently — mirror the i386 target's program list so drift
is visible.

## Notes / gates
- Track A: touches the Makefile cross targets + possibly the riscv32 backend if
  a widened program exposes a real codegen bug (then that's its own `bug-` under
  A). Gate = `make test-riscv32` green + no regression in `full`.
- Not urgent (riscv32 is perf-irrelevant and 32-bit), but it's a correctness
  blind spot, hence prio 35 over the rainy-day floor.
- xtensa has NO runtime coverage at all (bare-metal, un-qemu-able — emit-obj
  only); that's inherent, not this ticket.

## Log
- 2026-07-11 — filed from the tier-coverage panel.
