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

## Next-session prompt (start the ESP soft-float arc here)

> Track A. Build float support for the ESP targets (xtensa + riscv32), which today
> have NO float value model — even `a:=1.5; b:=a+2.0` errors `unsupported node in
> IR codegen`. Linux float returns are done (cross-float-returns, done/).
>
> Settled model (read feature-softfloat-lib.md + feature-esp-float.md first):
> Single=binary32(4B), Double=binary64(8B) on every target. `Real` = native float
> depth — Double on x86-64/i386/aarch64/arm32, Single on xtensa+riscv32. Dispatch:
> xtensa Single=HW single FPU + Double=soft; riscv32 Single=soft-single +
> Double=soft-double; double-native targets unchanged (Single storage-only/widen).
>
> Do it in order:
> 1. **THIS ticket first** (no codegen dep). New file
>    `compiler/builtin/softfloat.pas`, pure-Pascal IEEE-754 kernels. Land
>    soft-single first (`__pxx_sadd/ssub/smul/sdiv/scmp`), then soft-double
>    (`__pxx_d*`), then conversions (`i2s/s2i/i2d/d2i/s2d/d2s`). Round-nearest-even;
>    handle inf/nan/zero; denormals may flush-to-zero initially but **mul/div
>    rounding must match SSE**. Validate STANDALONE on x86-64: call the kernels
>    directly, diff vs native `+ - * /` over a value grid (large / tiny /
>    signed-zero / nan / inf / subnormal-adjacent). Mirror the existing soft-divide
>    in builtinheap.pas as the style template. Builtin = Track A's lane.
> 2. **feature-esp-float.** (0) target-aware `Real` resolver (parser.inc ~6513/6552:
>    Double on double-HW, Single on xtensa/riscv). (1) value model: Single=4B core
>    reg (riscv) / HW single reg (xtensa); Double=bits in a core-reg pair (riscv
>    a0:a1, xtensa a-pair) mirroring arm32 d0->r0:r1. (2) lower float IR nodes in
>    `ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`: literal / load / store /
>    binops / intrinsics / conversions / params / returns. riscv: single->soft-
>    single, double->soft-double. xtensa: single->HW FPU, double->soft-double. (3)
>    relax EmitProcEpilog guards LAST (symtab.inc ~3713 xtensa / ~3753 riscv32). (4)
>    wire float tests into the ESP/cross suites; QEMU output-equality vs the x86-64
>    oracle (no self-host on ESP).
> 3. Optional, later: `{$FASTDOUBLES ON|OFF}` (default OFF) — xtensa Double via
>    HW-single round-trip, fast/lossy. Post-baseline.
> 4. `feature-extended-alias-or-reject` — low; alias Extended->Double.
>
> Within each target: literal + load/store + compare first (unblocks branches),
> then add/sub, mul/div, conversions, params/returns.
> Rules: error-not-miscompile (leave unimplemented pieces erroring). x86-64
> untouched -> `make test` must stay byte-identical; if fixedpoint breaks it's a
> 1-gen reseed (`make bootstrap`), NOT non-determinism. Shared checkout with Track
> B: stay in compiler/** + compiler/builtin/**; `git commit -- <paths>`, verify
> `git show --stat`; Track B owns lib/rtl (don't touch). No push without user OK.
