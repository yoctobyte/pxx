# First-class Single (native single-precision arithmetic)

- **Type:** feature (type system + codegen, all targets)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

`Single` is currently a **storage-only** type. Every backend widens a Single to
double on load (`cvtss2sd` / `fcvt d,s` / VFP widen), computes in double, and
narrows back on store. There is no native single value channel. Grep:
ir_codegen386.inc:830 "Single widened to double", ir_codegen_aarch64.inc:1647,
ir_codegen_arm32.inc:850, ir_codegen.inc (x86-64 widen-on-result).

Consequences:
- Single arithmetic rounds like double, not like FPC Single (correctness drift on
  intermediate results).
- No memory/throughput win: a large `array of Single` matrix still rides the
  double ALU.
- Blocks using a hardware **single-only** FPU (ESP32 / S3) — see
  [[feature-esp-float]]: with first-class Single, those parts do single math in
  hardware and only need soft-float for Double.

This is the float analog of int32-vs-int64: a typed value channel the codegen
dispatches on, not a one-size cast.

## Goal

Make Single a real arithmetic type on every hardware-float target (x86-64, i386,
aarch64, arm32): native single load/store/add/sub/mul/div/compare/convert, single
value channel (xmm-ss / VFP s-reg), FPC-matching rounding. Mixed single/double
expressions still promote to double per Pascal rules; pure-single stays single.

## Approach (sketch)

1. Value-model bit: float IR nodes already carry a tk; thread whether the live
   value is single or double through the per-target emitters instead of forcing
   double. (Today the channel is always the double reg.)
2. Per target, add the single instruction forms alongside the double ones:
   - x86-64 / i386: `movss/addss/subss/mulss/divss/ucomiss/cvtsi2ss/cvtss2si`.
   - aarch64: `fadd/fmul/... .s`, `scvtf s`, `fcvtzs ... s`.
   - arm32: VFP `.f32` forms (already partly present for stores).
3. Promotion: a binop with one double operand widens the single side (existing
   widen path) and is double-typed; both-single stays single.
4. Params / returns / formatting: Single already has a 4-byte ABI slot on each
   target (the float-returns work handles the Single result reg); formatting goes
   through the same PXXWriteFloat* (convert single->double only at the format
   boundary, which is fine — printing is the one place double is correct).

## Notes / risk

- **No self-host reseed expected:** the compiler itself uses no `Single`, so
  changing single codegen shouldn't alter compiler.pas output bytes. Verify with
  `make test` fixedpoint after each target; if it breaks it's a shared-path leak,
  not non-determinism ([[feedback_codegen_reseed_not_nondeterminism]]).
- Correctness-first: get single rounding to match FPC (and the x86-64 SSE oracle)
  before chasing the memory-throughput payoff.
- Foundation ticket: do this before [[feature-esp-float]] (ESP hardware-single
  depends on it) and independent of [[feature-softfloat-lib]].
- Predecessor: [[feature-cross-float-returns]] (done) — float params/returns wiring
  per target, the Single result-reg handling is already in place.
