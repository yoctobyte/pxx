---
track: U
prio: 60
type: decide
---

# Decide: what a Variant unbox does when the tag does not match the target

Raised while landing [[bug-a-nilpy-variant-element-not-usable-as-scalar]]
(commit 8bd1ac4c). The ticket flagged this as a real decision; I shipped a
defensible default rather than blocking, so **this is a confirm-or-change,
not a blocker**.

## The fork

`VariantToInt64` / `VariantToDouble` / `VariantToBool` / `VariantToChar` in
`compiler/builtin/builtin.pas` must do *something* when the payload's tag is
not the requested class. Two families of case:

1. **Numeric <-> numeric <-> bool <-> char.** Not contentious: both Pascal's
   Variant and Python's numeric tower coerce. Shipped as coercion
   (VT_DOUBLE -> Trunc for an integer target, etc.). No decision needed.
2. **STRING payload, numeric target** (`i = xs[0]` where the element is
   `"ab"`). This is the genuine fork.

## Options for case 2

| | behaviour | argument for |
| --- | --- | --- |
| **A (shipped)** | halt with a runtime error | CPython raises TypeError here. Loud beats silent; this whole bug class was silent garbage, so inventing a number would re-create it in a new place. |
| B | parse the text (`Val`) | Pascal's Variant is historically coercive; convenient in scripty code. |
| C | yield 0 | never crashes; maximally silent — I'd argue against. |

## Recommendation

**Keep A**, and revisit only if a corpus program actually wants B. A is the
conservative direction: it can be relaxed to B later without breaking any
program that works today, whereas shipping B and tightening to A later breaks
working code.

Note the asymmetry deliberately left in place: the *other* direction (numeric
payload, STRING target) keeps `VariantToStr`'s existing coercive behaviour —
that is shipped semantics `str()` depends on, not mine to change here.

## If the answer is "keep A"

Close this and no code moves. If it is B or C, the change is confined to the
three `else` branches in the `VariantTo*` helpers.
