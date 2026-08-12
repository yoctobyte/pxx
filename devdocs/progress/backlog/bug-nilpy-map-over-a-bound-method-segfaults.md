---
track: N
prio: 50
type: bug
blocked-by: []
summary: "map(obj.method, xs) SEGFAULTS — a bound method is one of the four callable representations PyCallKey1 claims to handle, and it is the one that crashes. Pre-existing: measured identical on the eager map (pinned v263) and the lazy one, so laziness neither caused nor fixed it. list(map(f, xs)) with a def, a lambda or a builtin all work."
---

# `map(obj.method, xs)` segfaults

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-12, writing the acceptance test for
  [[feature-nilpy-lazy-iterator-objects]]. Not caused by it.

## Repro

```python
class Box:
    def __init__(self, k):
        self.k = k

    def scale(self, x):
        return x * self.k


b = Box(3)
print(list(map(b.scale, [1, 2])))     # CPython: [3, 6]
```

`SIGSEGV` (and `SIGILL` for the inline `map(Box(3).scale, ...)` spelling).

## It is PRE-EXISTING, measured

The control removes the variable rather than renaming it: the same file built
with the **pinned** binary (v263, whose `map` is still the eager list) crashes
identically. So this is the callable dispatch, not the cursor.

| callable passed to `map` | result |
| --- | --- |
| a plain `def` | works |
| a `lambda` (an interpreted pyeval source closure) | works |
| a builtin (`str`) | works |
| **a bound method (`obj.method`)** | **SIGSEGV, both eager and lazy** |

Three of the four representations `PyCallKey1` enumerates are fine; the
bound-pair arm is the one that faults
([[project_nilpy_callable_has_three_representations]]).

## Where to look

`PyCallKey1` (pyeval) branches on `PXXObjIsBoundPair(key)` first and calls
`m1(recv, a0)`. `sorted(key=obj.method)` goes through the same entry, so
whatever is wrong is likely visible there too — worth checking whether that
spelling crashes as well, since it would say whether the fault is in the
dispatch or in how `map`'s arm BUILDS the key from `obj.method`
(`PyGetOrMakeCallableWrapper` vs the bound-method value path).

The acceptance test `test/test_nilpy_lazy_map_filter.npy` covers the other
three shapes and carries a comment pointing here for the fourth; add the row
back when this is fixed.
