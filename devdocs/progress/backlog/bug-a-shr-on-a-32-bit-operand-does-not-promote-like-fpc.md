---
track: A
prio: 40
type: bug
blocked-by: [decide-shift-operator-promotion-width]
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

## Update 2026-08-10 — the measurement this ticket asked for

> "That wants its own measurement — starting with whether FPC promotes for
> `shl`, `and`, `or` and `div` in the same way, or only for `shr`."

Done, at `5fb29abbc`. Swept every integer operator against `fpc -O1` in three
operand forms (constant fold / Integer variable / Int64 control):
**`and`, `or`, `xor`, `div`, `not`, `+`, `-`, `*` all AGREE**, and the Int64
row has never disagreed. Only `shl` and `shr` on a 32-bit operand diverge.

`shl` diverges too, and not the same way `shr` does: FPC's `8 shl 40` is
**2048** — a 32-bit shift with the count masked to 5 bits — while its constant
fold `1 shl 40` is the full **2^40**. pxx answers **0** for both (64-bit
compute truncated to 32), which is a silent trap in its own right. So FPC
widens the operand for `shr` but masks the count for `shl`, and its folder
disagrees with its own runtime path.

That makes this a semantics choice rather than a fix, so it is now blocked on
**[[decide-shift-operator-promotion-width]]**, which carries the table, the
four options and a recommendation.
