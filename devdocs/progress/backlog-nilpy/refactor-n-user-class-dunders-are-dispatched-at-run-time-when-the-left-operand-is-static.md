---
slug: refactor-n-user-class-dunders-are-dispatched-at-run-time-when-the-left-operand-is-static
title: a user class's operator dunder is dispatched at run time even when the left operand's class is statically known
summary: >
  `v * k` where `v` is a statically-known user class and `k` is object-typed is
  CORRECT since the pylib one-sided-predicate fix, but it takes the runtime
  variant path: the blanket `tyVariant` arm in pasparser_expr.inc claims the pair
  before the user-class dunder arm below it is tested, so the node is typed
  tyVariant and the dunder is found by RTTI lookup per evaluation rather than
  bound at parse time. Costs a dynamic dispatch per operator in a hot loop and
  types the result tyVariant instead of the dunder's declared return type. No
  known wrong answer -- open as a typing/speed question, not a correctness one.
track: N
type: refactor
prio: 30
owner: unassigned
status: open
---

## What is there now

`compiler/pasparser_expr.inc`, two `else if` chains:

- `ParseTerm` (`* / // %`): the variant arm, then the user-class `__mul__` /
  `__truediv__` / `__floordiv__` / `__mod__` arm ~24 lines below it.
- `ParseSimpleExpr` (`+ -`): the variant arm at ~11163, the user-class
  `__add__` / `__sub__` arm ~91 lines below it.

```pascal
else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
  ASTTk[node] := Ord(tyVariant)
```

Either operand being a variant is enough, so a pair whose LEFT is a genuine
user class declaring the dunder never reaches the arm that would bind it.

The precedent for giving a statically-decidable arm precedence is already in the
same chain, forty lines up: the list-repeat and bytes-repeat arms were moved
ABOVE the variant arm for
`bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic`,
with the argument stated in its comment -- the repeat is decided by the SEQUENCE
operand, which is statically known, while the COUNT may be anything. A dunder
call is decided by the LEFT operand, which is equally statically known.

## Why it is a refactor and not a bug

Every observable is correct. `bug-n-arithmetic-on-a-user-class-fails-when-the-
other-operand-is-object-typed` was fixed in `compiler/builtin/pylib.pas` by
making the eight variant arithmetic entry points ask the one-sided question
("either side is a user object"), which is where a variant operand belongs and
which also covers the shapes with NO static class on either side. So the runtime
path answers correctly; the question here is only whether the compile-time path
should have claimed the pair first.

Two things it would buy:

1. **A dispatch per evaluation.** The runtime arm does `GetInstanceRTTI` plus a
   `PyFindDunder` string lookup on every operator evaluation. A vector demo
   doing `v * k` per frame per object pays that; a parse-time bind does not.
   NOT MEASURED -- measure before ranking this up.
2. **The result's static type.** The node is `tyVariant` where a parse-time
   dispatch would type it by the dunder's declared `RetType`. The list-repeat
   comment records the shape of what that costs when it matters: an inferred
   local holding a value with no class identity mis-picks an overload.

## Do NOT simply hoist the arm

Measured by reading, 2026-09-14: in `ParseSimpleExpr` the user-class dunder arm
has no `PyRecIsPylibOwnClass` exclusion (its sibling in `ParseTerm` does), and
it sits BELOW the bytes-concat, list-concat, dict-union and set-operator arms
that depend on being reached first. Moving it above the variant arm moves it
above those too, and `xs + ys` would be routed into a `TPyList.__add__` that
does not exist -- turning working list concatenation into a runtime TypeError,
which is exactly the failure `833f3ccba` repaired for the ordering arm.

The shape that works is to NARROW the variant arm rather than move anything:

```pascal
else if ((ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant))) and
        not PyUserDunderOwnsPair(op, left, right) then
```

with one predicate answering "does a user-class dunder arm below own this pair"
-- left is a genuine non-pylib user class declaring `PyBinOpDunderName(op)`, or
left is not a class and right declares `PyReflName(op)`. Guard it to the ops the
two arms actually handle (`+ - * / // %`), or a `&`/`|` pair with an `__and__`
on the left would skip the variant typing and land in the generic arithmetic
with no arm to catch it.

## Gate

`make test-nilpy` + self-host byte-identical. The rows that must not move are
`test_nilpy_variant_operand_arith_dunders` (both arrangements),
`test_nilpy_mixed_type_operands` (list comparison, which is what the ordering
arm's own exclusion protects) and the list/dict/set operator rows in
`test_nilpy_dunder_bitwise`.

## Log
- 2026-09-14 -- filed while resolving
  `bug-n-arithmetic-on-a-user-class-fails-when-the-other-operand-is-object-typed`
  at the runtime instead. The parser asymmetry was diagnosed by the peer session
  **lekkerzeilen-c8** and is correct; it turned out not to be the biting cause,
  and it is banked here rather than lost.
