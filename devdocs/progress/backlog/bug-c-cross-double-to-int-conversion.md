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
