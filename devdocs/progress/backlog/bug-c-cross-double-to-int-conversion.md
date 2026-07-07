---
prio: 45
---
# C double→int conversion missing on cross backends (i386/arm32/aarch64/riscv32)

- **Type:** bug (C→codegen, cross). Track C (shared codegen → file as A).
- **Found:** 2026-07-07, while fixing bug-c-float-single-precision on x86-64.

## Symptom
x86-64 now truncates a double assigned/passed to an integer target (cvttsd2si),
added in ir_codegen.inc (IR_STORE_SYM, IR_STORE_MEM, IR_CALL arg-push loops).
The cross backends (ir_codegen_i386/arm32/aarch64/riscv32.inc) have NO equivalent
double→int conversion, so `int x = 3.7;` / `charfunc(99.0)` still bit-copy the
raw double bits there.

## Fix
Mirror the x86-64 cvttsd2si sites in each cross backend's store + call-arg paths:
- aarch64: `fcvtzs`; arm32: softfloat __pxx_d2i (double→int kernel already exists
  for d2i64); i386: x87 fld/fistp or cvttsd2si; riscv32: softfloat d2i.
Reuse the existing double→int64 softfloat kernels (see v180 __pxx_d2i64) narrowed
to 32-bit where needed. C-mode only.

## Gate
A C float→int conversion test (mirror test/cfloat_conv_b176.c) byte-identical on
all cross targets; then fold into make test-lua-cross / relevant cross suite.


## Progress 2026-07-07 — i386 STORE_SYM done (SSE2 cvttsd2si)
i386 has SSE2, so it mirrors x86-64 directly. Added the double->int truncation in
i386 IR_STORE_SYM (ir_codegen386.inc): after the value is emitted (a float RHS
lands in xmm0), `cvttsd2si eax, xmm0` before the integer store. C-mode only.
Verified: `int x=3.7; char c=65.0; long l=9.9` -> 3 65 9 under qemu-i386; x86-64
unchanged; make test self-host byte-identical; test-i386 all-green.
REMAINING: i386 IR_STORE_MEM (field/element `s.i = 3.7`) + i386 C-call arg path
(`charfunc(99.0)`), then the ARM/riscv32 backends (aarch64 fcvtzs; arm32/riscv32
via the existing __pxx_d2i / softfloat kernels — see v180). Each per-backend,
gated by its qemu suite.


## STORE_SYM done on ALL 5 targets 2026-07-07
double->int on an integer assignment (`int x=3.7; char c=65.0; long l=9.9` ->
3/65/9) now works on x86-64 (cvttsd2si) + i386 (SSE2 cvttsd2si) + aarch64
(fmov+fcvtzs) + arm32 (VFP vcvt.s32.f64, long=32-bit) + riscv32 (softfloat
__pxx_d2i64, low word). Each verified under its qemu suite; all make-test +
test-<arch> green. REMAINING (lower priority): the IR_STORE_MEM (field/element
`s.i = 3.7`) and C-call arg (`intfunc(99.0)`) paths on the 4 cross backends —
mirror the same conversion at those sites. The assignment case (by far the most
common) is complete cross-target.


## STORE_SYM + STORE_MEM done + permanently gated on all 5 targets (2026-07-07)
Both store paths (assignment `int x=3.7` and field/element `s.i=3.7`,
`a[i]=3.7`) now truncate correctly on x86-64/i386/aarch64/arm32/riscv32, each via
the target's native path (cvttsd2si / fcvtzs / VFP vcvt.s32.f64 / softfloat
__pxx_d2i64). Permanently gated: test/ccross_double_to_int.c (STORE_SYM +
STORE_MEM + array element) wired into test-i386/aarch64/arm32/riscv32; b176 covers
x86-64. All suites green.

## REMAINING: C-call arg path (lower priority)
`intfunc(99.0)` — passing a float value to an INTEGER parameter — is not yet
converted on the 4 cross backends (x86-64 is done). This needs the double->int
truncation inserted into each backend's C-call argument marshalling (per-ABI:
i386 all-stack; aarch64 x0-x7; arm32 r0-r3+VFP; riscv32 a0-a7+softfloat), where a
float argument lands in an integer parameter slot. Rare construct (real C usually
passes an int or an explicit cast), so lower priority than the two store paths.
Same conversion primitives as above; mirror the x86-64 IR_CALL arg-push fix.
Test: extend ccross_double_to_int.c with an `intfunc(99.0)` case once landed.
