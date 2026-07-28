---
track: N
prio: 70
type: bug
---

# A mixed-type conditional in a comprehension element turns numbers into strings

Silent wrong values, found in songformatter's `convertrawtext.py`
([[feature-demo-songformatter-pxx-target]]).

```python
def f(fret_positions, barre):
    return ["x" if fret == "x" else fret - barre for fret in fret_positions]

print(f([1, "x", 3], 1))
```

CPython: `[0, 'x', 2]`
pxx:     `['0', 'x', '2']`

The conditional's two branches have different types (str and int), so the
element must be a VARIANT holding each value as it is. Instead every element is
coerced to a string: the arithmetic is performed and then stringified, so the
answer looks plausible and compares unequal to the number it should be.

The same comprehension with both branches numeric is correct, and so is the
mixed form when the source list is a local rather than a parameter — this
reproduces with the source coming in as a parameter (hence variant-typed).

## Second, related failure (does not compile at all)

Assigning that comprehension back to the parameter walls:

```python
def f(fret_positions, barre):
    fret_positions = ["x" if fret == "x" else fret - barre for fret in fret_positions]
    return fret_positions
```
```
error: Nil Python: pylib TPyList.append/add not loaded
  near:  x  fret  barre >>> for fret
```

which is the shape convertrawtext.py:224 uses. The message is misleading: the
appended element's type is what could not be resolved, not the pylib method.

## Why it matters beyond this app

`[a if cond else b for x in xs]` with branches of different types is ordinary
Python. Producing a plausible wrong value is the worst failure mode available —
worse than the compile error its sibling gives.

## Gate

`make test-nilpy` plus a `.npy` covering both shapes, diffed against CPython.
