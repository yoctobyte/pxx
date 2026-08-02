---
track: N
prio: 50
type: feature
---

# Starred and NESTED unpacking targets

- **Type:** feature (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.
- Extends [[feature-nilpy-tuple-unpack]], which landed the two-name forms and is
  done. These are the shapes it did not cover.

## Measured

```python
first, *rest = [1, 2, 3]        # error: undefined variable (first)
```

```python
nested = [(1, ("a", "b"))]
for n, (p, q) in nested:        # error: Nil Python: expected a second loop variable
    ...
```

Both are hard compile errors, so they are the good case.

## What already works (measured in the same sweep)

Worth stating, so this is scoped as an extension and not re-investigated from
scratch:

```python
for k, v in pairs: ...            # list of 2-tuples
for k, v in sorted(d.items()): ...
for a, b in zip(xs, ys): ...
for a, b in [[1, 2], [3, 4]]: ... # list of lists
head, tail = [9, 8]
a, b = b, a
```

All correct. So the machinery for a flat two-name target exists; what is missing
is (a) a STAR in the target list and (b) a target that is itself a target list.

## Shape

- **Starred**: `a, *b = xs` and `*a, b = xs`. The starred name takes a LIST of
  the surplus, so it needs a count computed at run time (`len(xs) - fixed`), not
  a compile-time slot count. Python allows exactly one star per target list —
  refuse two loudly rather than picking one.
- **Nested**: `for n, (p, q) in ...`. The target is a TREE, so the existing
  "expected a second loop variable" scan needs to recurse instead of assuming a
  flat name list. Same for the assignment form `a, (b, c) = ...`.

The two are independent; either can land alone.

## Gate

A `.npy` diffed against CPython covering: `a, *b`, `*a, b`, a star that captures
zero elements, nested targets one and two levels deep, nested inside a `for`,
the mixed form `a, (b, c) = ...`, and a too-few-values case (CPython raises
ValueError).
