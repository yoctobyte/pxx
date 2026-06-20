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

## Scope — soft SINGLE (primary) + soft DOUBLE (explicit-Double path)

Drives off the `Real` mapping (see [[feature-esp-float]] — open decision): FPC
maps `Real` to **Single** on no-FPU processors (double only where there's hardware
FP). If PXX follows FPC, the *common* float on riscv lowers to soft-**single** —
cheaper (32-bit mantissa math) and the precision FPC promises there. Explicit
`Double` still has to work, so soft-double is also needed, just not the hot path.

Kernels (both widths; single is the one to land first):
- single: `__pxx_sadd/ssub/smul/sdiv`, `__pxx_scmp`
- double: `__pxx_dadd/dsub/dmul/ddiv`, `__pxx_dcmp`
- conversions: `__pxx_i2s/s2i/i2d/d2i` (+ u-variants), `__pxx_s2d/d2s` (single<->
  double bit repack — pure integer)

Ordered, NaN-aware compares; round-to-nearest-even. Inf/NaN/zero handled;
denormals can be a documented follow-up (flush-to-zero first) — but **mul/div
rounding must be correct** or formatted decimal output diverges from the x86-64
oracle.

NOTE: if the project instead keeps `Real`=Double on all targets (numeric-
portability over FPC-fidelity), this collapses to double-kernels-only and single
rides the widen-to-soft-double path. That mapping decision gates this scope —
resolve it in [[feature-esp-float]] first.

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
