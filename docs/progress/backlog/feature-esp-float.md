# ESP float wiring (xtensa + riscv32 float value model)

- **Type:** feature (cross codegen depth, ESP targets)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

xtensa + riscv32 have **no float value model at all** — even `a:=1.5; b:=a+2.0`
errors `unsupported node in IR codegen`. This is why float function returns
couldn't be enabled there in [[feature-cross-float-returns]] (Linux targets done).

## Design — Single stays storage-only; Double is the work

The universal rule (every target, incl. these) is: `Single` is a 4-byte storage
type that **widens to Double for all arithmetic** and narrows on store. PXX has no
native single math and doesn't want any on double-capable hardware (the convert
overhead is cheaper than maintaining a second ALU path). So the real job on the
ESP targets is making **Double** work:

| target                     | double arithmetic | single |
|----------------------------|-------------------|--------|
| riscv32 (ESP32-C3, no FPU) | soft-float lib    | widen to soft-double |
| xtensa (ESP32 / S3)        | soft-float lib    | widen to soft-double (baseline) |

So the MVP is the same for both: a soft-double value model that calls
[[feature-softfloat-lib]]. Single just rides the widen path into soft-double.

### Optional optimization (xtensa only, defer)

xtensa has a hardware **single-precision** FPU. Pure-single code could run on it
instead of widening to soft-double — a speed win for single-heavy ESP workloads.
This is an OPTIMIZATION, not correctness, and only pays off on xtensa (riscv has no
FPU; double-capable targets already widen cheaply). Do it after the soft-double
baseline works, if/when single-on-ESP performance matters. Not on the critical
path.

## Dependencies

- [[feature-softfloat-lib]] — the soft-double kernels + s<->d / i<->d conversions
  this wiring calls. (No first-class-single ticket: storage-only-widen is the
  model, so there's nothing to make "first class".)

## Approach (per target, after the lib lands)

1. Value model: carry a Double as raw bits in a core-register pair (riscv a0:a1,
   xtensa a-pair), mirroring arm32's d0->r0:r1 spill.
2. Lower the float IR nodes (`ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`):
   literal, IR_LOAD_SYM / STORE (8-byte slot moves), binops -> soft-double helper
   calls, intrinsics, single-load = soft-widen to double, single-store = soft-
   narrow, then params + returns.
3. Relax the EmitProcEpilog float guards last (symtab.inc ~3713 xtensa /
   ~3753 riscv32) — only once arithmetic + params are correct.
4. Add float tests to the ESP/cross suites; QEMU output-equality vs the x86-64
   oracle (ESP self-host is not a goal — device RAM too small).

## Notes

- Order within: literal+load/store+`dcmp` first (unblocks comparisons/branches),
  then add/sub, mul/div, conversions, params/returns.
- error-not-miscompile: leave each unimplemented piece erroring; never ship silent
  garbage.
- The float-return/param recipe from [[feature-cross-float-returns]] applies
  verbatim once arithmetic exists.
