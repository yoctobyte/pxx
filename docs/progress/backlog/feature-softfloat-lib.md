# Soft-float library (IEEE-754 single + double kernels)

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

## Goal

A standalone `compiler/builtin/softfloat.pas` of plain-Pascal IEEE-754 kernels,
target-independent (integer bit-twiddling only, so it cross-compiles to any
backend). Single + double:

- `__pxx_sadd/ssub/smul/sdiv` and `__pxx_dadd/dsub/dmul/ddiv`
- `__pxx_scmp/dcmp` (-1 / 0 / 1; ordered, NaN-aware)
- conversions: `__pxx_i2s/s2i/i2d/d2i/s2d/d2s` (and u-variants as needed)

Round-to-nearest-even. Inf/NaN/zero handled; denormals can be a documented
follow-up (stub/flush-to-zero first) — but the **rounding in mul/div must be
correct** or formatted decimal output diverges from the x86-64 SSE oracle.

## Approach

1. Pure library first, no codegen wiring: implement + unit-test the kernels by
   calling them directly from a test program on x86-64, comparing results to
   native SSE `+ - * /` over a value grid (including subnormal-adjacent, large,
   tiny, signed-zero, NaN/Inf inputs). This validates the math independent of any
   ESP backend.
2. Reuse the existing `PXXWriteFloat*` formatters for the comparison harness once
   a double can be produced.
3. The codegen lowering that *calls* these helpers is a separate ticket per
   no-FPU target — see [[feature-esp-float]].

## Notes

- Lives in builtin (compiler-emitted helper calls), Track A's lane — not lib/rtl.
- Keep it allocation-free and syscall-free (runs on bare metal).
- Decompose/normalize/round is the bulk; ~a few hundred lines. Bounded, like the
  soft-divide already in builtinheap.pas (the template to mirror).
- Consumers: [[feature-esp-float]] (riscv soft single+double, xtensa soft double).
  Hardware-FPU targets never call these.
