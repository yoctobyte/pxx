---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`type(2 ** 70).__name__` answers `<unknown>` where CPython answers `int` — an arbitrary-precision (promo/variant) integer has no name in the type() mapping, while a machine int, float, str, list and every user class do"
status: done
owner: claude-AN
---

# `type()` of an arbitrary-precision int answers `<unknown>`

- **Type:** bug (wrong value, small) — **Track N**
- **Found:** 2026-08-12, while fixing
  [[bug-nilpy-a-def-returning-a-big-int-expression-directly-answers-zero]] —
  the values became correct and only the type NAME stayed wrong, which is how
  it separated out.
- **Pre-existing:** the bind-to-a-local spelling (`x = 2 ** 70; type(x)`) has
  always worked value-wise and has always answered `<unknown>` here.

```python
print(type(2 ** 70).__name__)     # pxx: <unknown>    CPython: int
x = 2 ** 70
print(type(x).__name__)           # pxx: <unknown>    CPython: int
print(type(7).__name__)           # both: int
```

Every other kind answers correctly — `int` for a machine int, `float`, `str`,
`list`, `dict`, `bool`, `NoneType`, and a user class by name. It is specifically
the promotable/variant-boxed integer that falls off the end of the mapping.

## Why it is worth fixing even though it is small

`type(x).__name__` is the supported spelling in this frontend (a bare
`type(x)` is refused with a diagnostic naming it), so it is what a NilPy program
uses to branch on a value's kind — and a big int reporting `<unknown>` makes
that branch take the wrong arm. It is also the sort of thing a test asserts
alongside a value, which is where it will be met.

## Where to look

The `type(x).__name__` lowering's kind-to-name mapping (pyparser.inc), and
whatever it does for `tyPromoInt64` and for a VT_PROMO_INT64-tagged variant at
run time. Both spellings need the row: the static promo type and the runtime
tag, since a big int reaches the call either way.

## Gate

A `.npy` diffed against CPython: `type().__name__` of `2 ** 70`, of a wide
literal, of a promo local, of a big int out of a def and out of a list element,
plus the machine-int / float / str / bool / list / None / user-class rows in the
same file as controls.

## Log
- 2026-08-12 — resolved, commit 2adec8b8e.
