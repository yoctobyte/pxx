---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`s.update(other)` on a SET is a compile error (\"TPyList has no method update\") though CPython accepts it. The operator spelling `s |= other` works and lowers to TPyList.setupdate, so only the METHOD NAME is missing — the same Python-name-to-pylib-name mapping dict already has for items/keys/values."
---

# `set.update()` is refused — only the `|=` spelling reaches setupdate

- **Type:** bug (refused valid program) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-13, while sweeping sibling shapes for
  [[bug-n-inline-multi-entry-dict-literal-arg-loses-its-values]] (an unrelated
  argument-counting bug; this one surfaced in the same sweep and is its own
  defect).
- CPython accepts and runs this, so it is a real N bug rather than a
  laxer-than-CPython divergence (`devdocs/dev/nilpy-semantics-divergences.md`).

## Repro

```python
t = set()
t.update({4, 5, 6})
print(len(t))          # CPython 3 — pxx: compile error
```

```
pascal26:2: error: Nil Python: TPyList has no method update
```

## What works, and why that pins the cause

`s |= other` lowers fine, and pylib does implement the operation — as
`TPyList.setupdate` (`compiler/builtin/pylib.pas:132`), because a set IS a
TPyList here (`devdocs/dev/threading-model.md:109`). So the runtime is present
and correct; what is missing is the Python spelling `update` being mapped onto
it for a set receiver.

There is already a place that does exactly this kind of mapping for the other
container: `PyParseClassMethodCall` rewrites `items`/`keys`/`values` to
`itemlist`/`keylist`/`vallist` when the receiver's class is TPyDict
(`compiler/pyparser.inc`, near the top of that function), with the variant
receiver path (`PyParseVariantMethod`) carrying its own copy of the same table.

## The catch that makes this more than a one-line alias

`update` is ALSO a TPyDict method, and a set and a list are the same class here
(TPyList), so the mapping cannot be keyed on the class alone the way the dict
view methods are — a genuine list has no `update` in Python and should keep
saying so. Whoever picks this up should decide whether the receiver's
set-vs-list nature is known at that point or whether this wants a runtime arm.
That question is the reason this is filed rather than fixed in passing.

## Grep the siblings before closing

Set methods generally, for the same "operator works, method name missing"
shape: `difference_update`, `intersection_update`,
`symmetric_difference_update`, `issubset`/`issuperset` (pylib has
`setintersect`, `issubset` — check which spellings the frontend actually
routes), and `discard`/`add`.

## Gate

`make test-nilpy` + self-host fixedpoint; a `.npy` test diffed against CPython
covering `update`, the `|=` control, and a plain list's `update` still being
refused.
