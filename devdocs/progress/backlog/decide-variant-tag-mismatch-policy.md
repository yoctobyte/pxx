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

## RESOLVED IN SHAPE 2026-07-20 — helpers are now per-language

The user's call: *"we can just craft our own when needed — python obviously
needs other helpers. as long our AST is shared, i don't care for duplicating
helpers because of syntax variations."*

So this is no longer one policy question. Commit d3754ee3 split the helpers:
NilPy uses pylib's `pyvar_to_int/float/bool/char`, Pascal keeps builtin.pas's
`VariantTo*`, and `ir.inc` picks the set under `PyProgramMode`.

- **The NilPy half is SETTLED**: Python's rules, TypeError on a str/object in
  a numeric slot, total truthiness for bool. Nothing further to decide.
- **The Pascal half is now a separate, smaller question** — see the compat
  note at the end.

The options table below is kept because it is still the argument for the
NilPy answer.

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

## What is actually left: the PASCAL half (compat)

`VariantToInt64`/`ToDouble` currently HALT on a string payload. That is not a
regression — before the unbox landed, Pascal's `i := v` returned the TAG, so
halting is strictly better than what shipped. But Delphi/FPC's Variant is
historically COERCIVE (`i := v` on `'42'` yields 42), so FPC parity probably
wants B for Pascal.

**Unverified: fpc is not installed on this box**, so there is no oracle for
the exact FPC behaviour and the claim above is from recollection, not a
measurement. Do not implement Pascal-side coercion on it — run FPC first.
Re-file as `compat-pascal-variant-coercion` when a box with fpc is available.

Note also that `VariantToBool` was written with PYTHON truthiness ('' and 0.0
false) while Pascal was still routed through it; that is fixed by the split,
but the Pascal helper's semantics were never separately specified and should
be checked against FPC at the same time.
