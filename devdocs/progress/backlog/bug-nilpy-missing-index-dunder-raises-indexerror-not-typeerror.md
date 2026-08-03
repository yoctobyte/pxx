---
track: N
prio: 35
type: bug
summary: "Indexing a sequence with an object that has no __index__ raises IndexError (the handle used as a position) where CPython raises TypeError — loud but misleading, and a small handle would index the wrong element instead"
---

# A missing `__index__` at a subscript raises IndexError, not TypeError

- **Type:** bug (NilPy semantics, misleading diagnostic) — **Track N**
- **Found:** 2026-08-03, closing
  [[bug-nilpy-unary-numeric-dunders-return-raw-handle]]. Everything that ticket
  covered is fixed; this is the not-declared half of `__index__`.

## Measured

```python
class N: pass
xs = [10, 20, 30]
xs[N()]        # CPython: TypeError    pxx: IndexError: list index out of range
```

The instance HANDLE is used as the position. It raises only because the handle
is far past the end — a small enough handle would silently index the wrong
element, which is the shape this whole family keeps producing.

## Why it was not fixed with the rest

Raising needs to know the receiver is a SEQUENCE, and the site that would raise
does not know. `PyIndexCoerce` sees only the index expression, and it is called
from a dict subscript too, where an object IS a legal key. Getting this wrong in
the obvious place collapsed object dict keys onto their `__index__` value —
measured, and recorded on the parent ticket.

`PyClassWantsIntIndex` (added there) is the predicate to reuse: it already
answers "does this receiver want an integer". The work is threading the raise
through the sites that have the receiver, and choosing a pylib raiser
(`PyUnsupportedOperandError` is the nearest existing one; Python's own message
is "list indices must be integers or slices, not N").

## Gate

A `.npy` diffed against CPython: list, str and bytes subscripted by an object
with no `__index__`, each inside a `try/except TypeError` that must run its
handler; a dict subscripted by the same object, which must still WORK; and the
declared-`__index__` cases still green.
