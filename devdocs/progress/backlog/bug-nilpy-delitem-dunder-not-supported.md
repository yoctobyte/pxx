---
prio: 30
track: N
type: bug
blocked-by: []
---

# `del obj[k]` does not dispatch `__delitem__`

- **Type:** bug / missing protocol (NilPy) — **Track N**
- **Split out of** [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] 2026-08-09
- **Loud:** a compile error, not a wrong answer.

```python
class C:
    def __delitem__(self, k):
        print("DELITEM", k)

c = C()
del c[3]        # CPython: DELITEM 3
```

```
pascal26:5: error: Nil Python: del is supported on a dict subscript or a list slice
```

Re-measured at HEAD 2026-08-09: unchanged.

## Why this is the smallest of the three siblings

`del` already lowers a dict subscript and a list slice, and the error message
above enumerates exactly the arms that exist. This is one more arm on a
construct that is already there — a user class whose class declares
`__delitem__` — not new machinery.

Its siblings `__getitem__`/`__setitem__` are already dispatched
(`test_nilpy_dunder_getitem_setitem.npy`), so `__delitem__` is the odd one
missing out of the three-member subscript protocol. Follow that test's lowering.

## Gate

`.npy` diffed against CPython: `del c[k]` on a class declaring `__delitem__`,
a class declaring `__getitem__` but NOT `__delitem__` (must raise TypeError, as
CPython does, not compute), and controls that `del d[k]` on a dict and
`del xs[i:j]` on a list are unchanged.
