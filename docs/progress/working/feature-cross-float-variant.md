# Float + Variant codegen on cross targets

- **Type:** feature
- **Status:** working
- **Owner:** Antigravity <antigravity@google.com>
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-11 (user request)

## Motivation

The cross backends are integer/pointer only. No floating-point (`tySingle`/
`tyDouble`/`tyExtended`) and no `Variant` (16-byte tag+payload) codegen. This
blocks compiling the full `builtin` unit on cross targets — `FloatToStr`,
`VariantToStr`, and `Str`/float paths use float arithmetic and variant ops — and
therefore blocks the cross self-host (`uses SysUtils` pulls these in).

## Scope

### Floats
- `IR_BINOP` float arith + compare, float `IR_WRITE` (the `EmitWriteFloat*`
  family), float load/store, int↔float conversion, float literals.
- i386: x87 or SSE2 (SSE2 is the simpler, modern choice; 32-bit SSE2 is
  baseline on any real i686). ARM32: VFP. AArch64: native FP/SIMD (v0..v31).
- Float **parameter ABI** per target (ties to feature-cross-param-abi):
  x86-64 SSE class, AArch64 v-regs, ARM32 VFP/soft-float, i386 stack/x87.

### Variants
- `IR_VAR_STORE` / `IR_VAR_BINOP` / `IR_VAR_BOX` / `EmitVariantClear` /
  `EmitVariantRetain` / `EmitWriteVariant` on cross targets. The 16-byte slot is
  the same layout everywhere; the managed payload (string) release already has
  portable helpers.
- Consider moving variant box/clear/compare bodies into portable Pascal helpers
  (as with the string/record runtime) to minimise per-arch emission.

## Acceptance

Float and Variant test programs compile and run on i386, ARM32, AArch64 with
output identical to x86-64. The full `builtin` unit compiles on every target.
New `test/test_cross_float.pas` and `test/test_cross_variant.pas` in the suites.

## Staging

Floats and Variants can land as two separate slices; floats first (broader
value, and `builtin`'s `FloatToStr` needs them).
