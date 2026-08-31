---
track: N
prio: 25
type: feature
summary: "NilPy: `while x in (\"a\",\"b\")` now rebuilds the constant tuple on every test. A provably-constant container build is loop-invariant and should be hoisted to a variable once — what a person would write by hand — while everything else keeps being folded into the condition."
---

# Hoist a constant container literal out of a loop condition

- **Type:** feature (optimization) — **Track N**
- **Raised by:** the user, 2026-08-06, while
  [[bug-nilpy-a-method-call-in-a-while-condition-is-evaluated-once]] was being
  fixed: *"in python, it would be totally fair to move a const list or dict to a
  variable, to avoid all double cases (variable or const)"*.

The principle behind it — normalise the special shape into the general one so
downstream has a single path — is written up in
**`devdocs/dev/normalise-dont-special-case.md`**, which this ticket is the
motivating instance of. Read that before implementing; it also states the
safe-direction rule the predicate below has to obey.

## Where this comes from

A `while` condition's hoisted setup used to be emitted once, before the loop.
That was right for a constant literal and wrong for a string method call, which
hoists identically and is not loop-invariant — the condition went stale and the
loop spun. The fix folds each sub-expression's setup into the sub-expression, so
everything is now recomputed per test.

Correct, and for a constant it is needless work:

```python
while x in ("a", "b"):    # the tuple is rebuilt on every test
    ...
```

CPython rebuilds it too, so this is not a divergence — just an allocation per
iteration that a hand-written program would not pay, because a person would
write `AB = ("a", "b")` above the loop.

## What to build

Split the hoisted chain at the point it is folded (`PyFoldHoistSince`,
`compiler/pyparser.inc`): a statement that is **provably** a constant container
build stays hoisted OUTSIDE the loop as before; everything else keeps being
folded in.

The predicate is the whole risk, and it must be conservative in the SAFE
direction — **fold unless proven constant**, never the reverse. A container
literal hoists as `__py_lit* := TPyList.Create` followed by N `append` /
`setitem` calls, so "provably constant" means: the assigned symbol is one of
those hidden literal temps, and every argument of every call in the chain is a
literal node (`AN_INT_LIT` / `AN_STR_LIT` / bool / None), recursively. Anything
else — a name, a call, a subscript — fails the test and gets folded.

Getting that backwards reinstates exactly the bug above, silently. That is why
it was not done inline with the fix.

## Worth checking while in there

Whether the same split is wanted for `if` conditions and comprehension filters,
which share the hoist machinery. If it is, do them together — the last several
bugs in this family were all "one path was fixed and its sibling was not".

## Gate

Per-fix loop. Extend `test/test_nilpy_while_condition_hoist.npy`: the constant
tuple/dict conditions must keep their values (already covered), and add a
NON-constant container in a loop condition (`while x in (a, b)` over variables,
and `while x in (f(), g())`) to prove those are still folded and still see fresh
values. Diff against CPython with `tools/pydiff.py`.
