# C `unsigned int` / Pascal Cardinal division+mod use signed div on 32-bit backends

- **Type:** bug (correctness) — Track A (shared codegen)
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** split off from [[bug-c-unsigned-int-32bit-arithmetic-semantics]]
  (resolved 2026-06-30); that ticket fixed unsigned arithmetic wrap + compares,
  this is the remaining division/mod signedness gap.

## Symptom

On i386/arm32/riscv32, `unsigned int` (C) and `Cardinal`/`LongWord` (Pascal) `/`
and `%` (mod) emit **signed** divide for scalar (32-bit) ordinals, so operands
with bit 31 set divide as negative. x86-64 is correct (keys on
`TypeDivideUnsigned`).

```c
unsigned int a = 3000000000u;   /* > 2^31 */
printf("%u\n", a / 7);          /* x86-64: 428571428   32-bit backends: wrong (signed idiv) */
```

## Root cause

Scalar ordinal divide/mod is hardcoded signed:
- i386:    `ir_codegen386.inc` ~1743 — `cdq; idiv ecx` (tkDiv/tkMod), always signed.
- arm32:   `ir_codegen_arm32.inc` ~1323 — `sdiv r0,r0,r1`, always signed.
- riscv32: `ir_codegen_riscv32.inc` ~955 — `div`/`rem`, always signed.

The 64-bit pair paths already honor `signedOp` (EmitBinop64_386 / …Arm32 /
…RISCV32). Only the scalar 32-bit path ignores signedness.

## Fix

Mirror the x86-64 `TypeDivideUnsigned(IntToTypeKind(IRTk[left]))` decision per
backend: i386 `xor edx,edx; div ecx`; arm32 `udiv`; riscv32 `divu`/`remu`. Same
shape as the compare-signedness fix in the parent ticket. 32-bit-backend-only, so
x86-64 self-host stays byte-identical; gate = cross green + a guard test (unsigned
div/mod with a >2^31 operand, exit-code or oracle-diff) on each 32-bit target.

## Acceptance

- Unsigned `/` and `%` on i386/arm32/riscv32 match x86-64/gcc for operands >= 2^31.
- Pascal Cardinal/LongWord div/mod unchanged where already correct; cross green.
- Guard test added.
