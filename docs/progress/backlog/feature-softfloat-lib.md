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

## Scope — soft SINGLE + soft DOUBLE + conversions

Settled by the `Real`-mapping decision (see [[feature-esp-float]]): `Real` = the
target's native float depth, so on no-FPU riscv the common float lowers to
soft-**single** (cheaper, and what `Real` resolves to there). Explicit `Double`
must work on every target, so soft-double is needed too. Land single first (it's
the riscv `Real` hot path and smaller).

Kernels:
- single (land first): `__pxx_sadd/ssub/smul/sdiv`, `__pxx_scmp`
- double: `__pxx_dadd/dsub/dmul/ddiv`, `__pxx_dcmp`
- conversions: `__pxx_i2s/s2i/i2d/d2i` (+ u-variants), `__pxx_s2d/d2s` (single<->
  double bit repack — pure integer)

Ordered, NaN-aware compares; round-to-nearest-even. Inf/NaN/zero handled;
denormals can be a documented follow-up (flush-to-zero first) — but **mul/div
rounding must be correct** or formatted decimal output diverges from the x86-64
oracle.

(xtensa never calls the single kernels — its `Real`/Single use the hardware single
FPU; it calls only the soft-DOUBLE kernels for explicit `Double`.)

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
