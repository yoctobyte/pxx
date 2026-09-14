---
slug: bug-n-a-comprehension-rename-rewrites-a-member-and-a-keyword-name
title: a comprehension's loop-target rename rewrote the member after a dot and a call's keyword-argument name
summary: >
  PyRenameIdentRange rewrites every ident token in a range that spells the
  loop target. Two positions carry that spelling without being a reference to
  it: the MEMBER after a dot and a call's KEYWORD ARGUMENT name. So
  `[name.name for a, b, name in rows]` raised
  `AttributeError: 'T' object has no attribute '__py_cv58_2'` and
  `[f(step=1) for step in xs]` was refused with
  `f has no parameter named '__py_cv23_0'` -- both naming a hidden identifier
  the source never wrote. Fixed in the helper, not at the four call sites,
  because it is a property of the token and true for all of them. Fixture
  test_nilpy_a_comprehension_rename_leaves_a_member_and_a_keyword_name_alone.
track: N
type: bug
prio: 85
owner: frank-user
status: done
---

## What it was

`compiler/pyparser.inc`, `PyRenameIdentRange`. Four callers, all renaming a
BINDING to a hidden name: the three comprehension sites and the except-handler
one. All four passed a token RANGE, and the helper renamed every matching
ident in it.

    [name.name for a, b, name in rows]    ->  the member `name` was renamed
    [f(step=1) for step in xs]            ->  the keyword `step` was renamed

Neither token is a reference to the loop target. A member name belongs to the
receiver's class; a keyword name belongs to the callee's signature.

## Why the two earlier fixes did not reach it

Both previous repairs in this area moved the RANGE. The narrowing recorded at
`pyparser.inc:26002` is correct and stays: a clause's own iterable is evaluated
in the ENCLOSING scope, so the stretch before the next `for`/filter is left
alone. But no range can express "this token is a member and that one is a
variable", so the range-shaped fixes could not have covered it. That is why
this one goes in the helper.

The note at `pyparser.inc:26012` already cited `lekkerzeilen ui.py:683` as the
attribute shape -- with a ONE-name target. This instance is slot **2** of a
three-name target, which is the slot neither earlier fixture reached, and it is
the CLAUDE.md interesting-element-last rule landing for the third time in this
subsystem.

## How it presented

After the promotable-int boxing fix
(`bug-n-a-promotable-int-field-is-boxed-as-an-object`) lekkerzeilen advanced
past its TypeError and died at

    Unhandled exception: AttributeError: 'Tile' object has no attribute '__py_cv558859_2'

`__py_cv<tok>_<slot>` is `PyCompHiddenLoopName`, so the message names the
compiler's own hidden identifier and nothing in the program.

## The fix

Two `Continue`s in the helper: skip a token preceded by `.`, and skip one
preceded by `(` or `,` and followed by `=`. The second also correctly skips a
lambda parameter's default name (`lambda a, x=...`), which is a binding too.

## Guard

`test_nilpy_a_comprehension_rename_leaves_a_member_and_a_keyword_name_alone`.
Rows whose target spelling is unused are the positive control; the colliding
rows follow; the three-name target is last. Reverted, the fixture does not
even build -- `f has no parameter named '__py_cv169_0'`.

## Log
- 2026-09-14 — resolved, commit 9b5b1be3b.
