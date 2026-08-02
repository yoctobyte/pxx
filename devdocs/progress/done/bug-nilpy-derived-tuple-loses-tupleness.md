---
track: N
prio: 60
type: bug
---

# A derived tuple decayed into a list

- **Type:** bug (NilPy, silent wrong output) — **Track N**
- **Found and FIXED:** 2026-08-02, by a differential sweep against the CPython
  oracle.

## Measured

```python
t = (1, 2, 3)
print(t)          # (1, 2, 3)   correct — always was
print(t[1:])      # CPython (2, 3)              pxx [2, 3]
print(t[:2])      # CPython (1, 2)              pxx [1, 2]
print(t[::-1])    # CPython (3, 2, 1)           pxx [3, 2, 1]
print(t + (4,))   # CPython (1, 2, 3, 4)        pxx [1, 2, 3, 4]
print(t * 2)      # CPython (1, 2, 3, 1, 2, 3)  pxx [1, 2, 3, 1, 2, 3]
```

The original tuple always printed correctly. It only decayed once you DERIVED
something from it — which is why this survived: every test that built a tuple
and printed it looked right.

## Cause

One representation (`TPyList`) backs both list and tuple, distinguished only by
an `FIsTuple` flag. So every operation that constructs a NEW sequence has to
carry the flag explicitly, and four did not:

| path | before |
| --- | --- |
| `pylist_slice` | fresh list, flag dropped |
| `pylist_concat` | fresh list, flag dropped |
| `pylist_repeat` | fresh list, flag dropped |
| `reversed` (which `[::-1]` lowers to) | fresh list, flag dropped |

Notably the VARIANT-dispatch repeat path already carried it, with the comment
`{ (1, 2) * 2 is a tuple, not a list }` — so the behaviour depended on which
path the operands took. That inconsistency is the tell.

`reversed` needed care: CPython's returns an ITERATOR, whose repr pxx does not
reproduce anyway, so carrying the flag there changes nothing that currently
matches the oracle while making `t[::-1]` correct. `list(reversed(xs))` still
builds a plain list, verified.

For `concat`, the LEFT operand's flag is taken — Python refuses to concatenate a
list with a tuple at all, so that matches wherever the expression is legal.

## Verified

`test/test_nilpy_tuple_identity.npy`, wired into `make test-nilpy`,
byte-identical to CPython. Confirmed RED pre-fix on all five derived forms.

Covers the derived tuples, the mirror-image cases (a LIST must not become a
tuple through the same four operations), the conversions that should yield a
plain list (`list()`, `sorted()`, `list(reversed())`), and a one-element tuple's
trailing comma.

## Noted, not fixed

`tuple([1, 2])` — the `tuple()` constructor is undefined (`undefined variable
(tuple)`). Loud, so a different family; recorded in
[[bug-nilpy-sweep-gaps-pow-thousands-sep-stepped-slice]].
