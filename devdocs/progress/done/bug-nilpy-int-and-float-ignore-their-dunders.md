---
track: N
prio: 40
type: bug
commit: 6e1271684
blocked-by: []
summary: "`int(obj)` and `float(obj)` asked the object nothing — they handed the conversion intrinsic an object HANDLE, so `int(V(4))` printed 129729065648272 for a class that declares __int__. A class declaring neither now raises CPython's TypeError instead of printing a pointer."
---

# `int()` and `float()` ignore `__int__` / `__float__`

```python
class V:
    def __init__(self, n): self.n = n
    def __int__(self): return self.n
    def __float__(self): return float(self.n)

print(int(V(4)), float(V(4)))
# CPython 4 4.0
# pxx     129729065648272 129729065648328.0
```

Silent, and the printed value is the instance POINTER, so it changes per run —
the tell of a handle read as a number. Found 2026-08-15 by a CPython
differential sweep of the numeric dunder surface, in the same pass that found
[[bug-nilpy-int-of-a-division-reads-the-doubles-bits]].

`bool`, `abs` and unary minus over the same class were already correct
(`__bool__`, `__abs__`, `__neg__` are dispatched), which is what makes this two
missing members of a protocol the frontend otherwise implements rather than an
absent feature.

## Fix

Both conversion intercepts now check for a user class first and call the dunder,
the same way the truthiness path calls `__bool__`. A class declaring NEITHER
gets a run-time `TypeError` naming it, in CPython's own message shape
(`PyNoIntError` / `PyNoFloatError`, beside the `PyNoSetitemError` pair they are
modelled on) — at RUN time, so `try: int(o) / except TypeError:` still compiles.

pylib's own container classes are excluded, keeping their existing paths.

## Gate

`test/test_nilpy_int_float_dunders.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: both dunders through a named receiver, a fresh
construction and a call result; a class declaring only `__int__` (whose
`float()` must still raise); a class declaring neither, for both conversions;
and the ordinary int/float/str/expression conversions unchanged. `gate.sh
quick` GREEN, pinned v331.
