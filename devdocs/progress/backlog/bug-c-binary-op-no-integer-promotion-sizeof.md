---
prio: 45
---

# `sizeof(us + 0)` reports 2, not 4 — binary ops skip the integer promotions

- **Type:** bug (compat — wrong type, currently benign)
- **Track:** C — C frontend (`cparser.inc`); tag: compat
- **Status:** backlog — opened 2026-07-12.
- **Found by:** while fixing [[bug-c-unary-minus-no-integer-promotion]] (same family).

## Symptom
```c
unsigned short us = 1;
sizeof(us + 0)   /* -> 2.  C says 4: both operands promote to int */
```
Same on every target, so it is CONSISTENT — which is why c-testsuite 00200 passes
anyway (its PTYPE macro takes sizeof on both sides and the error cancels). That is
luck, not correctness.

## Root cause (expected — verify before fixing)
The usual arithmetic conversions promote any operand narrower than `int` to `int`
before the operation. AN_BINOP's result type does not go through
`CIntegerPromoteTk`, so a `unsigned short + int` keeps the narrow type.

Unary `-` and `~` are now both fixed to promote; the BINARY operators are the
remaining member of the family.

## Why it is filed, not fixed
Unlike the unary case, the binary result type feeds codegen widely (widths, signed
vs unsigned compares, division). Changing it deserves its own gate and its own
bisect, not a drive-by at the end of an unrelated fix.

## Gate
C tests green + self-host byte-identical + cross (all targets — this touches every
backend's arithmetic widths).
