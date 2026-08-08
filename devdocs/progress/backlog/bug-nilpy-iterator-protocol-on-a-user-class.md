---
prio: 35
track: N
type: bug
blocked-by: []
---

# `for x in <user object>` does not use `__iter__`/`__next__`

- **Type:** bug / missing protocol (NilPy) — **Track N**
- **Split out of** [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] 2026-08-09
- **Loud:** a compile error, not a wrong answer.

```python
class Countdown:
    def __init__(self, n):
        self.n = n
    def __iter__(self):
        return self
    def __next__(self):
        if self.n <= 0:
            raise StopIteration
        self.n -= 1
        return self.n

for x in Countdown(3):      # CPython: 2 1 0
    print(x)
```

```
pascal26:11: error: Nil Python: pylib (count) not loaded
```

The for-loop lowering assumes a pylib container and looks for `count`. Re-
measured at HEAD 2026-08-09: unchanged.

## Why this is the biggest of the three siblings

It is not a name to bind but a protocol to teach the loop lowering: call
`__iter__` once, then `__next__` per step, and terminate on `StopIteration`
rather than on an index reaching a length. `StopIteration` as a control-flow
signal is the part with no existing analogue in the loop code — an exception
that must be caught by the LOOP, invisibly, and not propagate.

Generators (`yield`) are a different and much larger feature; this ticket is
only the explicit iterator-class protocol.

## Worth checking first

Whether the runtime dunder dispatch added 2026-08-08/09 (`PyFindDunder` +
`PyUserObjBoolDunder`/`PyUserObjObjDunder` in `pylib.pas`) can carry the
`__next__` call, so the loop lowering only has to emit the protocol and not
re-solve "find a method on a class known only at run time".

## Gate

`.npy` diffed against CPython: an explicit iterator class, one used twice
(a fresh `__iter__` each time), a class with `__iter__` but no `__next__`
(TypeError), and a control that iterating a plain list/dict/str is unchanged.
