---
track: U
prio: 45
type: decision
status: resolved
resolved: 2026-08-10
blocked-by: []
---


## DECIDED 2026-08-10 — native width by default; copy FPC's bugs only under `--strict-fpc`

**User's call.**

> "seems both implementations are wrong. look, it depends on int type. and pascal
> uses native int unless otherwise specified. so, pxx truncating to 32-bit is
> wrong (unless we explicitely specified 32 bit). but, i'd also say, let FPC do
> what they think is wrong or right, and (for now) we do what we think is wrong
> or right, BUT, in strict_FPC mode we _will_ copy their bugs." — user

### The rule

1. **Default dialect: shifts happen at NATIVE width (64-bit on x86-64), fold and
   runtime alike, with no truncation of the result.** One rule for `shl` and
   `shr`, no constant-vs-variable split.
2. **`--strict-fpc`: reproduce FPC exactly**, asymmetry and all — `shr` widens
   the operand to 64, `shl` masks the count to 5 bits at 32-bit width, and the
   constant folder keeps its own 64-bit answer. Explicitly "copy their bugs".

### Why native, and where the principle actually bites

Measured 2026-08-10: `Integer` is **4 bytes in both pxx and FPC** on x86-64
(`LongInt`=4, `NativeInt`=8, `Int64`=8). So `var a: Integer` IS an explicit
32-bit specification — the "native unless otherwise specified" principle does not
override a declared type.

Where it bites is the **untyped literal**: `1 shl 40` has no declared type, so it
is native, and pxx answering **0** is simply wrong. That is the trap this fixes,
and it is an everyday bitmask idiom.

For a DECLARED 32-bit operand we still promote rather than truncate, because the
alternative is a silent wrong value: a 64-bit computation truncated back to 32
is how `1 shl 40` became 0 in the first place. Widening never loses information;
truncating does.

### What this costs in FPC agreement — less than expected

| row | FPC | pxx after this change |
| --- | --- | --- |
| `1 shl 40` (const) | 1099511627776 | **1099511627776** — agrees |
| `-8 shr 1` (const) | 9223372036854775804 | **9223372036854775804** — agrees |
| `-a shr 1` (var, Integer) | 9223372036854775804 | **9223372036854775804** — agrees |
| `a shl b` (8 shl 40) | 2048 (count masked mod 32) | 2^43 — **diverges** |
| Int64 operands | — | agrees (unchanged) |

So native width agrees with FPC on three of the four disputed rows. The single
divergence is FPC's count-masking, which is the wart that its own constant folder
already contradicts — and `--strict-fpc` reproduces it for anyone who needs it.

### Scope

Only `shl` / `shr` on a 32-bit operand. Measured 2026-08-10: `and`, `or`, `xor`,
`div`, `not`, `+`, `-`, `*` all already agree with FPC in every operand form, and
Int64 operands have never disagreed. **Nothing outside the two shift operators
moves.**

Nothing has to be un-blessed: `test/test_const_precedence.pas` deliberately
asserts neither answer for this row.

### Now unblocked

[[bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc]] was blocked on this
and becomes ordinary Track A work — with the note that its title is now slightly
wrong: the fix is not "promote like FPC", it is "promote to native", which
happens to agree with FPC on `shr`.


# Decide: what width do `shl` / `shr` happen at for a 32-bit operand?

- **Type:** decision (Track U) — semantics, affects result types and overload
  selection everywhere.
- **Blocks:** [[bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc]], which
  filed itself rather than guessing and asked for exactly the measurement below.

## The measurement (2026-08-10, `5fb29abbc`, `fpc -O1 {$mode objfpc}`)

Every integer operator, three operand forms. **Only the shifts diverge.**

| op | constant fold | Integer variable | Int64 (control) |
| --- | --- | --- | --- |
| `and` `or` `xor` `div` `not` `+` `-` `*` | agree | agree | agree |
| **`shl`** | FPC `1 shl 40` = **1099511627776**, pxx **0** | FPC `a shl b` (a=8,b=40) = **2048**, pxx **0** | agree |
| **`shr`** | FPC `-8 shr 1` = **9223372036854775804**, pxx **2147483644** | same split | agree |

So the arithmetic and bitwise operators already promote to 64 bits in both
implementations, and the Int64 row has never disagreed. The whole question is
the two shift operators on a 32-bit operand.

## What each implementation is actually doing

- **`shr`** — FPC widens the OPERAND to Int64 and shifts logically, so
  `-8 shr 1` is `(2^64-8) >> 1`. pxx shifts the 32-bit pattern `$FFFFFFF8`.
- **`shl`** — FPC does **not** widen the variable form: `8 shl 40` = 2048, i.e.
  a 32-bit shift with the count **masked to 5 bits** (40 mod 32 = 8). Its
  CONSTANT fold, though, is 64-bit: `1 shl 40` = 2^40. pxx computes at 64 bits
  and truncates to 32, giving 0 for both.

**Note the asymmetry — it is FPC's, not ours.** `shr` widens the operand;
`shl` masks the count instead. And FPC's own constant folder disagrees with its
own runtime path for `shl`. Any "just match FPC" instruction has to swallow all
three of those.

## Options

1. **Match FPC exactly**, warts included: `shr` promotes the operand to Int64;
   `shl` masks the count at 32 for a variable operand but folds constants at 64.
   Maximum compatibility for ported code that relies on either behaviour.
   Cost: two different width rules for two sibling operators, plus a
   fold-vs-runtime split, and `shr` on an Integer starts producing Int64 —
   which changes result types, overload selection, and the width of everything
   downstream.
2. **Promote both operands to 64 bits, consistently** (fold and runtime).
   `1 shl 40` and `-8 shr 1` both give FPC's constant-fold answer; `8 shl 40`
   gives 2^43, where FPC says 2048. One rule, no fold/runtime split, and it is
   what a reader expects. Diverges from FPC on the masked-count case.
3. **Keep 32-bit shifts and mask the count**, i.e. adopt FPC's `shl` rule for
   both operators. `-8 shr 1` = 2147483644 (today's pxx answer, blessed);
   `8 shl 40` = 2048. Cheapest, no result-type churn, and matches the hardware.
   Diverges from FPC on `shr` and on constant folds.
4. **Status quo** — 64-bit compute truncated to 32. This is the one option with
   nothing to recommend it: it agrees with neither FPC nor the hardware, and
   `1 shl 40` silently being 0 is a trap.

## Recommendation

**Option 2**, with option 1 available behind `--strict-fpc` if a real corpus
ever needs it. It is one rule, it removes the fold-vs-runtime split, and it
makes the trap (`1 shl 40` = 0) impossible. The house style is FPC-faithful by
default — but this is a case where FPC is internally inconsistent, and
reproducing an inconsistency costs us a permanent second code path in a place
(integer width) where a second path is exactly what causes silent wrong values.

Whichever way it goes, `test/test_const_precedence.pas` currently asserts
neither answer for this row, on purpose — so nothing is blessed yet, and no
test has to be un-blessed.

## Not part of this decision

`Int64` operands already agree, and so does every non-shift operator. Nothing
outside `shl`/`shr` on a 32-bit operand should move.


---

## 2026-08-11 — the COST of this ruling, corrected (claude-A)

The table in the "What this costs in FPC agreement — less than expected" section
above listed ONE divergence. Implementing it (`a3f51dce1`) showed there are
four, and that the table understated it for a specific reason worth recording:

> its `-a shr 1` row agreed with FPC only because **FPC's unary minus on an
> Integer already yields Int64**, so that row never exercised `shr`'s own width.


The table's `-a shr 1` row agreed with FPC for a reason that does not
generalise: **FPC's unary minus already widens an Integer to Int64**, so that
row never exercised `shr`'s own width. A plain shift on a declared 32-bit
variable does, and there FPC keeps the operand's width:

| row | FPC | pxx (as decided) |
| --- | --- | --- |
| `i shr 1`, `i: Integer = -8` | 2147483644 | **9223372036854775804** |
| `i shl 31`, `i: Integer = 1` | -2147483648 | **2147483648** |
| `l shr 9`, `l = -2147483648` | 4194304 | **36028797014769664** |
| `l shl 1`, `l = -2147483648` | 0 | **-4294967296** |
| `a shl b` (8 shl 40) | 2048 | 8796093022208 |
| `1 shl 40`, `-8 shr 1`, `1 shl 31` (const) | — | agree |
| Int64 operands | — | agree (unchanged) |

In every row pxx keeps the bits FPC discards. And **two tests DID have to be
re-blessed** — `test/test_shift_operand_width.pas` and `test/test_shr_width.pas`
asserted the operand-width answers row by row. Both now assert the native ones,
with the divergence spelled out in the file.

## Why it is probably still right

The principle behind the ruling survives the bigger table: widening never loses
information, truncating does, and `1 shl 40 = 0` was the trap. The RTL was
checked and is unaffected — SHA-256 and CRC32 still produce correct digests,
because their intermediates land in `LongWord` variables and the STORE narrows.
The risk is code that consumes a shift result WITHOUT storing it to a sized
variable (a comparison, a `WriteLn`, an argument), which is where the four rows
above bite.

## If this changes your mind

1. **Keep it** (status quo, shipped): one rule, native width everywhere.
2. **Promote only an UNTYPED operand** — a literal is native, a declared
   `Integer`/`Cardinal` keeps its width. Fixes `1 shl 40` and leaves all four
   rows above matching FPC. This is the "a declared type IS an explicit width
   specification" half of the original decision's own reasoning, which the final
   rule then overrode.
3. Keep it, and bring `--strict-fpc` forward (it is not implemented yet — see
   `bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths`).

**Not re-filed as a decision.** The ruling stands as made; this is the cost
record it should have had. If the four rows above change your mind, the
alternative is: The divergent rows are all cases where FPC
throws bits away; anyone who wants that behaviour is asking for a 32-bit result
and can declare one. But the table above is what you were not shown on
2026-08-10, so the call is worth re-confirming rather than assuming.


Also implemented since: `--strict-fpc` reproduces FPC's shift widths for anyone
who needs them — 9 of 10 rows, the 10th being that unary-minus semantic rather
than a shift (`f27a32595`, `bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths`).
