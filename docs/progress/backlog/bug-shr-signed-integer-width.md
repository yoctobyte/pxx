# `shr` on a negative 32-bit Integer shifts at 64-bit width (miscompile)

- **Type:** bug (codegen / correctness) — Track A
- **Status:** backlog
- **Opened:** 2026-06-23
- **Found by:** differential probe vs FPC.

## Problem

`x shr n` where `x` is a signed 32-bit `Integer` holding a NEGATIVE value shifts
the 64-bit sign-extended register, so the sign bits leak in:

```pascal
var x: Integer; begin x := -8; writeln(x shr 1); end.
// pxx = 9223372036854775804   fpc = 2147483644
```

FPC does the logical shift at the operand's declared width (32-bit). Positive
Integer, `Cardinal`, and `shl` are all correct — only negative signed `shr`
miscompiles (silent wrong result). `and`/`or` masks are fine.

## Cause / fix

A 32-bit signed operand is sign-extended into the 64-bit register, then `shr` is
a 64-bit logical shift. Fix: for `shr` on a <64-bit operand, operate at the
operand width (zero-extend to the type width first, or use a width-sized shift),
so the high bits above the type width don't participate. Per-backend (the shift
lowering is in each `ir_codegen_*`); verify vs FPC for Byte/Word/Integer signed
and unsigned. Gate: `make test` + `make cross-bootstrap`.
