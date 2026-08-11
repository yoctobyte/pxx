---
track: U
prio: 45
type: decision
blocked-by: []
---

# Confirm: native-width shifts cost more FPC parity than `decide-shift-operator-promotion-width`'s table showed

- **Type:** decision (Track U) — a **confirmation**, not a fork. The rule is
  implemented and shipped as decided; this asks whether the fuller cost is still
  the trade you want.
- **Raised:** 2026-08-11, implementing
  [[bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc]].

## What was decided

> "Default dialect: shifts happen at NATIVE width, fold and runtime alike, with
> no truncation of the result. One rule for `shl` and `shr`, no
> constant-vs-variable split." — [[decide-shift-operator-promotion-width]],
> 2026-08-10

That is exactly what landed. Nothing here contradicts it.

## What the decision's cost table said

One divergence from FPC: `a shl b` (8 shl 40) — FPC masks the count to 5 bits.
Everything else was listed as agreeing, and it said "nothing has to be
un-blessed".

## What it actually costs, measured

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

## The fork, if you want one

1. **Keep it** (status quo, shipped): one rule, native width everywhere.
2. **Promote only an UNTYPED operand** — a literal is native, a declared
   `Integer`/`Cardinal` keeps its width. Fixes `1 shl 40` and leaves all four
   rows above matching FPC. This is the "a declared type IS an explicit width
   specification" half of the original decision's own reasoning, which the final
   rule then overrode.
3. Keep it, and bring `--strict-fpc` forward (it is not implemented yet — see
   `bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths`).

**Recommendation: keep it (1).** The divergent rows are all cases where FPC
throws bits away; anyone who wants that behaviour is asking for a 32-bit result
and can declare one. But the table above is what you were not shown on
2026-08-10, so the call is worth re-confirming rather than assuming.
