---
track: N
prio: 50
type: bug
---

# `list.reverse()` was missing

- **Type:** bug (missing list method — loud) — **Track N**
- **Found and FIXED:** 2026-08-02, by a differential sweep against the CPython
  oracle.

## Measured

```python
xs = [5, 3, 1]
xs.reverse()
```
```
error: Nil Python: TPyList has no method reverse
```

The two forms that build a NEW sequence — `reversed(xs)` and `xs[::-1]` — both
worked. Only the in-place method was absent, which is the one you use when you
mean to mutate.

## Fix

`TPyList.reverse` swapping ends inward (rather than building a copy — that is
what "in place" is for), returning `Self` so the statement lowering can use it
as a value node, the same shape `sort()` and `extend()` already use.

## Verified

`test/test_nilpy_list_reverse.npy`, wired into `make test-nilpy`,
byte-identical to CPython: the double-reverse identity, empty and
single-element lists, a mixed-type list, and confirmation that
`reversed()` / `[::-1]` still leave the original untouched.

## Context

The only gap in that sweep. The rest agreed with CPython: dict assignment,
iteration, `in`, `del`, `.items()`, `.clear()`; list `sort`/`insert`/`pop`/
`remove`/`extend`/`copy`/`clear`; set literals with duplicates; nested
dict-of-list mutation; and a nested-comprehension matrix with element
assignment. Container mutation is in good shape.
