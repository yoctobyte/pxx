# Cross-target float function results

- **Type:** feature (cross codegen depth)
- **Status:** working
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

Float-typed function results (`function F: Double` / `Single` / `Extended`)
**error on every cross target**:

```
target <arch>: only ordinal/pointer/string function results supported yet
```

(symtab.inc EmitProcEpilog, one guard per target: i386 ~3497, arm32 ~3613,
aarch64 ~3679, xtensa ~3710, riscv32 ~3750.)

This is the last broad float gap on cross targets. `feature-cross-float-variant`
(done) already landed float arithmetic, mixed int/float, comparisons, intrinsics
(Trunc/Round/Frac/Int), formatting, params, and consts; and int→float **assign**
already works cross (e.g. aarch64 ir_codegen_aarch64.inc ~855 does `scvtf`).
Only the function-**return** path was never enabled.

## Approach

The internal value model carries a float as its raw double-bits in the
**integer return register** (x0 / r0 / eax(:edx) / a2 / a0) — the same register
EmitLoadVar* already targets for ordinals. So enabling float returns is mostly
relaxing the per-target guard to allow `TypeIsFloat`, then confirming the result
load writes the full width into the return reg (8 bytes for Double; Single is
widened to double-bits by EmitLoadVar* already). 64-bit-in-2-regs targets (i386
eax:edx, arm32 r0:r1) need the Int64-style two-word load for an 8-byte Double.

Internal calls only — external C float returns have their own ABI path
(test_extern_c_float, already green).

## Plan / status
- [x] **aarch64 — DONE.** Value model carries floats as bits in x0 (= the return
  reg); guard relaxed to allow `TypeIsFloat`, EmitLoadVarA64 already loads the
  Double's 8 bytes / widens a Single into x0. Float PARAMS already worked on
  aarch64. test/test_cross_float_return.pas wired into the aarch64 cross suite.
- [ ] arm32 — float RETURN alone works (d0 convention; verified `NoParam:Double`),
  BUT float PARAMS are broken on internal calls (verified: `OneDbl(9.0)` →
  garbage). Reverted to erroring for now (the project rule is error-not-miscompile,
  and a half-enable would silently mis-pass float-param functions). Needs BOTH
  param-passing + return together.
- [ ] i386 — same: needs param + return (errors cleanly today).
- [ ] xtensa — needs param + return (errors cleanly today).
- [ ] riscv32 — needs param + return (errors cleanly today).
- [ ] gate: make test + cross-bootstrap + cross suites green

## KEY FINDING (2026-06-20)

Float function results were never enabled, which ALSO meant float PARAMETERS were
never exercised on internal cross calls — any float-param function hit the return
guard first and errored. So on arm32/i386/xtensa/riscv the work is **both**:
1. caller: pass a float arg in the target's call-arg registers (e.g. arm32 d0 →
   r0:r1 for Double / r0 for Single; the prologue word-spill at parser.inc ~7987
   may already reconstruct the slot correctly — verify);
2. callee: return the float in the convention the caller consumes.
aarch64 needed neither (bits-in-x0 = both arg and return reg already). Each
remaining target is its own ABI slice; do one at a time, QEMU-tested, then add it
to that target's cross suite.

## Log
- 2026-06-20 — Opened from the result-in-loop / int-to-float arc, which found the
  guard. Scoped: value model already float-bits-in-int-reg, so this is guard
  relaxation + result-load width per target, not new float infrastructure.
