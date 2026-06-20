# Soft-float library (IEEE-754 double kernels + conversions)

- **Type:** feature (builtin library, target-independent)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

Targets without a hardware FPU (riscv32 / ESP32-C3 now; future no-FPU parts) need
software IEEE-754 arithmetic. There is none today. The existing pure-Pascal
soft-integer-divide lives in `compiler/builtin/builtinheap.pas`, but soft-float is
substantial and conceptually distinct — it gets **its own library file**, not a
graft onto builtinheap.

## Scope — DOUBLE only (single rides the widen path)

PXX models `Single` as storage-only: it widens to Double for all arithmetic and
narrows on store (this is the right model — see [[feature-esp-float]]). So a
no-FPU target's Single code just widens to a **soft-double**, computes there, and
narrows. That means this library needs **no separate soft-single arithmetic** —
only double kernels plus the width conversions:

- `__pxx_dadd/dsub/dmul/ddiv`
- `__pxx_dcmp` (-1 / 0 / 1; ordered, NaN-aware)
- conversions: `__pxx_i2d/d2i` (+ u-variants), `__pxx_s2d/d2s` (single<->double bit
  repack — pure integer, no FPU)

Round-to-nearest-even. Inf/NaN/zero handled; denormals can be a documented
follow-up (flush-to-zero first) — but **mul/div rounding must be correct** or
formatted decimal output diverges from the x86-64 SSE oracle.

## Approach

1. Pure library first, no codegen wiring: implement + unit-test the kernels by
   calling them directly from a test program on x86-64, comparing to native SSE
   `+ - * /` over a value grid (large, tiny, signed-zero, NaN/Inf,
   subnormal-adjacent). Validates the math independent of any ESP backend.
2. Reuse the existing `PXXWriteFloat*` formatters for the harness once a double can
   be produced.
3. The codegen lowering that *calls* these helpers is per no-FPU target —
   [[feature-esp-float]].

## Notes

- New file `compiler/builtin/softfloat.pas`. Builtin (compiler-emitted helper
  calls), Track A's lane — not lib/rtl.
- Allocation-free, syscall-free (runs bare metal).
- Decompose/normalize/round is the bulk; ~a few hundred lines. Bounded, mirrors the
  soft-divide already in builtinheap.pas.
- Consumers: [[feature-esp-float]] (riscv all-soft; xtensa soft-double only —
  xtensa single uses its hardware single FPU, not this lib).
