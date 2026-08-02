---
track: N
prio: 40
type: bug
summary: "class D(B, C): does not parse — a second base is an 'unexpected token' at the comma, so multiple inheritance and every mixin idiom is unavailable"
---

# `class D(B, C):` does not parse

- **Type:** bug / missing language feature (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping previously-unswept surfaces vs CPython.
- **Loud**: a parse error, not a silent wrong answer.

```python
class A:
    def who(self):
        return "A"

class B(A):
    def who(self):
        return "B"

class C(A):
    def who(self):
        return "C"

class D(B, C):     # <-- error: unexpected token, at the ','
    pass

print(D().who())   # CPython: B  (MRO: D, B, C, A)
```
```
pascal26:22: error: unexpected token
  near:    D  B >>>  C
```

Single inheritance works. Only the comma is rejected, so the class header
parser evidently takes exactly one base.

## Why this is prio 40 and not higher

It fails loudly at compile time, and single inheritance covers the overwhelming
majority of real NilPy code. But it blocks every **mixin** idiom, which is how
a lot of ordinary Python is structured, so it will keep being hit by corpus work.

## The real cost is the MRO, not the parse

Accepting the comma is the easy half and is NOT the feature. Python resolves
attributes by C3 linearisation, so `D().who()` must give `"B"` — and with a
diamond (both B and C deriving from A) the order is D, B, C, A, which is
observable whenever two bases define the same name. The underlying Pascal
object model is single-inheritance, so a second base cannot be a real parent.

Options, roughly in order of honesty:

1. **Full C3 with explicit dispatch** — flatten the linearisation at compile
   time and resolve each attribute to the winning definition. Correct, and the
   most work.
2. **Second base as a delegate** — real inheritance from the first base, and
   attributes not found there forwarded to an embedded instance of the second.
   Handles mixins, gets the diamond wrong in the case where C3 would pick C
   over an inherited-from-A member of B.
3. **Refuse a second base explicitly** — replace "unexpected token" with a
   diagnostic naming multiple inheritance. Cheap, honest, and strictly better
   than today's error, which reads like a parser bug.

Option 3 is worth doing immediately regardless of which of 1/2 is chosen later.
Do NOT accept the comma and silently ignore the second base: that turns a
compile error into a wrong method being called at run time.

## Gate

A `.npy` diffed against CPython covering: a plain mixin (bases with disjoint
methods), a diamond where the MRO is observable, and `isinstance` against both
bases.
