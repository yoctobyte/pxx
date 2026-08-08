---
prio: 30
track: N
type: bug
blocked-by: []
---

# `bytearray` and `bytes` are the same type — repr, type name and mutability

- **Type:** bug (NilPy, observable divergence) — **Track N**
- **Found:** 2026-08-09 while closing
  [[feature-nilpy-runtime-method-dispatch-on-variant]]
- **Owner:** —

```python
b = bytearray([1, 2])
print(b)                    # CPython bytearray(b'\x01\x02')   pxx b'\x01\x02'
print(bytes([1, 2]))        # CPython b'\x01\x02'              pxx b'\x01\x02'
print(type(b).__name__)     # CPython bytearray                pxx bytes
```

Both map to one `TPyBytes`, so they are indistinguishable in repr and in
`type().__name__`.

## Why it is a real bug and not laxity

It survives the upward-compatibility rule: a program CPython accepts and runs to
completion observes the difference. Printing a bytearray is the obvious case;
branching on `isinstance(x, bytearray)` or on `type(x).__name__` is the one that
silently takes the wrong path.

The deeper half is **mutability**: `bytes` is immutable in CPython and
`bytearray` is not, so `b[0] = 5` must work on one and raise on the other. If
NilPy allows it on both, code that relies on bytes being immutable (a dict key,
a shared constant) has no guard.

## Shape of a fix

`TPyList` already carries an `FKind` discriminator to tell a list from a tuple
from a set — three Python types over one class, with the kind deciding repr,
`type().__name__` and `isinstance`. `TPyBytes` wants the same treatment: one
field, set at construction, consulted by the renderer, the type-name answer, the
isinstance test and any mutating method.

Follow `PYSEQ_TUPLE`'s example rather than inventing a second mechanism — and
note the lesson recorded there: a display that fails to STAMP the kind is a
wrong *type*, not just wrong brackets, so every construction site must set it.

## Gate

`.npy` diffed against CPython: repr of both, `type().__name__` of both,
`isinstance` against each, round-tripping one into the other
(`bytes(bytearray(...))`), and `b[0] = 5` succeeding on a bytearray while
raising TypeError on a bytes.
