---
summary: "qword + non-negative literal demoted to Int64: correct bits, but writeln/hi()/comparisons treated the result as SIGNED"
type: bug
prio: 50
---

# QWord ⊕ non-negative literal: result/comparison domain demoted to signed

- **Type:** bug (silent wrong values — signed print, wrong hi() width, wrong
  ordering). **Track P** (shared parser typing) — filed per "board = the
  record"; fixed in the same night session that found it.
- **Status:** done
- **Opened:** 2026-07-14, found in the tint642 burn-down right behind
  [[bug-pascal-qword-to-double-signed]].

## What happened

`$f0000000` (> maxint) widens to tyInt64 at parse. The equal-width
"signed wins" rule then made:

- `q + $f0000000` → tyInt64: bits correct, but `writeln` printed it negative
  and `hi()` keyed a 32-bit width off the demoted type ($F303 instead of
  $FAFAFAFA).
- `q > $f0000000` → SIGNED compare: any q ≥ 2^63 ordered wrong.

FPC's range-based constants join the unsigned domain when non-negative.

## Fix (same session)

Two parser sites:
- arithmetic binop typing: a non-negative AN_INT_LIT paired with a tyUInt64
  operand types the result via (tyUInt64, tyUInt64);
- relational binop: the literal operand node is RETAGGED tyUInt64 so codegen's
  TypeCompareUnsigned sees two unsigned operands.

Negative literals keep the signed domain (`q + (-1) = q - 1` verified).

## Verification

test_qword_literal_binop.pas (Makefile-registered) — all rows byte-identical
to FPC 3.2.2 output. tint642 now runs through lo/hi and typecasts; its sole
residual is {$Q+} overflow-checked arithmetic (skip entry updated).

## Log
- 2026-07-14 — resolved, commit 6590369e.
