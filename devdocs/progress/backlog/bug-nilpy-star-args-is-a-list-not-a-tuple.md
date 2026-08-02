---
track: N
prio: 40
type: bug
summary: "`*args` inside a function is a LIST, so it prints as [2, 3] where CPython prints (2, 3) and type(args).__name__ is 'list' rather than 'tuple'"
---

# `*args` is a list, not a tuple

- **Type:** bug (NilPy semantics — visibly wrong output) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
def m(a, *args):
    return args

print(m(1, 2, 3))                     # CPython: (2, 3)    pxx: [2, 3]
print(type(m(1, 2, 3)).__name__)      # CPython: tuple     pxx: list
```

## Cause, and why it is nearly fixed already

pxx backs a Python tuple with `TPyList` and marks the instance so it RENDERS with
parentheses — `pylist_mark_tuple` exists for exactly this, and
[[bug-nilpy-str-of-tuple-is-empty]] and
[[bug-nilpy-derived-tuple-loses-tupleness]] are the two tickets that built and
then repaired that mechanism.

The `*args` packing path simply does not call it. So this is very likely a
one-line fix at the site that builds the packed argument list, not a
representation question — the representation already exists.

## Impact

Cosmetic in the common case, real in two:

- any program that prints or logs `*args` shows the wrong bracket
- `type(args).__name__` and `isinstance(args, tuple)` answer wrongly, which is
  the kind of check argument-forwarding wrappers actually make

## Gate

A `.npy` diffed against CPython: `print(args)` for zero, one and several extra
arguments; `type(args).__name__`; `args` forwarded to another `*args` function
and printed there; and a genuine list parameter alongside, to confirm the marking
is not applied too widely.
