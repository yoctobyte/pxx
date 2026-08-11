---
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
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

## Resolution (2026-08-11) — native width, per the decision

Implemented [[decide-shift-operator-promotion-width]]'s default half: a shift's
RESULT is typed at native width when the left operand is a narrower machine int
(signed → NativeInt, unsigned → NativeUInt), and both 64-bit backends obey that
tag — x86-64 and aarch64 sign-extend a narrow SIGNED operand before the logical
`shr` (instead of zero-extending it) and skip `shl`'s narrow-back when the
result is native. One rule for both operators, no constant-vs-variable split.
C is untouched: `CProgramMode` keeps the declared-width wrap the standard
requires, and its `<<`/`>>` still match gcc.

The 32-bit targets need no change and got none — native there IS 32 bits, so
i386/arm32/riscv32 keep today's answers.

**The cost is larger than the decision's table showed**, and that is worth
knowing: the table's `-a shr 1` row agreed with FPC only because FPC's unary
minus already widens, so it never exercised `shr`'s own width. A plain shift on
a declared 32-bit variable diverges — four rows, listed in
`decide-shift-native-width-costs-more-fpc-parity-than-the-table-showed`, filed
so the user can re-confirm the call on the full table rather than the partial
one. Two tests had to be re-blessed (`test_shr_width`,
`test_shift_operand_width`), where the decision expected none; both now state
the divergence in the file rather than quietly asserting new numbers.

Verified: the 10-row shift matrix against `fpc -O1` (8 rows agree; the two that
do not are FPC's count-masking, which its own folder contradicts), identical
answers on aarch64, `make lib-test` GREEN, SHA-256 and CRC32 digests still
correct (their intermediates land in `LongWord`, so the STORE narrows), the C
shift matrix still matching gcc, and a 139-file bit/int/cast/const family sweep
against `pinned` with no diffs beyond the intended ones.

`--strict-fpc`'s half is not implemented — filed as
`bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths`.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
