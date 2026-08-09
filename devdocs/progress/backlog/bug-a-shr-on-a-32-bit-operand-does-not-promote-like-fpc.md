---
track: A
prio: 40
type: bug
blocked-by: []
---

# `shr` on a 32-bit operand shifts at 32 bits; FPC promotes to 64 first

- **Type:** bug (FPC-semantics divergence, silent) — **Track A**
- **Found:** 2026-08-09, isolating
  [[bug-a-unary-minus-binds-looser-than-and-shr]]. Once the binding was fixed,
  this is what remained.
- **Pre-existing.**

```pascal
var x: Integer;  x := 8;
WriteLn(-x shr 1);
```

| | |
| --- | --- |
| FPC | `9223372036854775804` — promotes the operand to Int64, then a logical shift |
| pxx | `2147483644` — logical shift of the 32-bit pattern `$FFFFFFF8` |

Both are honest LOGICAL shifts; they disagree on the WIDTH they happen at. An
`Int64` operand already agrees (`-y shr 1` gives FPC's answer on both), so this
is only the 32-bit-operand row.

## Why it is filed rather than fixed alongside the binding

Changing `shr`'s result width is an integer-promotion question, not a grammar
one: it would make every `shr` on an Integer produce an Int64, which changes
result types, overload selection and the width of everything downstream. That
wants its own measurement — starting with whether FPC promotes for `shl`,
`and`, `or` and `div` in the same way, or only for `shr`.

`test/test_const_precedence.pas` deliberately does NOT assert either answer for
this row, with a comment saying so, so neither is blessed by a passing test.

## Gate

`-x shr 1` matching FPC for `x: Integer`, without changing the `Int64` row that
already agrees, and with the C frontend's `>>` (arithmetic on signed, gcc-
verified) untouched.
