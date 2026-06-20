# ESP float wiring (xtensa hardware-single + soft-double; riscv32 all-soft)

- **Type:** feature (cross codegen depth, ESP targets)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

xtensa + riscv32 have **no float value model at all** — even `a:=1.5; b:=a+2.0`
errors `unsupported node in IR codegen`. This is why float function returns
couldn't be enabled there in [[feature-cross-float-returns]] (Linux targets done).

## The capability matrix (the whole design)

Each (target × type) cell is either a hardware instruction or a soft-float call:

| target                          | single | double |
|---------------------------------|--------|--------|
| x86-64 / i386 / aarch64 / arm32 | HW     | HW     |
| xtensa (ESP32 / ESP32-S3)       | **HW** (single FPU) | soft |
| riscv32 (ESP32-C3)              | soft   | soft   |

So:
- **xtensa**: wire native single-precision FPU ops (the part has a single FPU);
  Double goes through soft-float kernels.
- **riscv32**: both single and double via soft-float kernels.

## Dependencies

1. [[feature-single-first-class]] — needed so xtensa can do single math in
   hardware instead of widening to a (soft) double. Do this first.
2. [[feature-softfloat-lib]] — the `softfloat.pas` kernels xtensa-double and all
   of riscv call.

## Approach (per target, after deps land)

1. Value model: carry a double as raw bits in a core-register pair (riscv a0:a1,
   xtensa a-pair), mirroring arm32's d0->r0:r1 spill; carry a single as 4 bytes in
   one core reg (riscv) or an FPU s-reg (xtensa).
2. Lower the float IR nodes (`ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`):
   literal, IR_LOAD_SYM / STORE (slot moves), binops, intrinsics, then params +
   returns. Dispatch per the matrix: hardware insn (xtensa single) vs helper call
   (everything soft).
3. Relax the EmitProcEpilog float guards last (symtab.inc ~3713 xtensa /
   ~3753 riscv32) — only once arithmetic + params are correct.
4. Add float tests to the ESP/cross suites; QEMU output-equality vs the x86-64
   oracle (ESP self-host is not a goal — device RAM too small).

## Notes

- Order within: single+cmp first (unblocks comparisons/branches), then add/sub,
  mul/div, conversions, params/returns.
- error-not-miscompile: leave each unimplemented piece erroring; never ship silent
  garbage.
- The float-return/param recipe from [[feature-cross-float-returns]] applies
  verbatim once arithmetic exists.
