---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`self.v = n` in the ctor then `self.v = 1.5` (or `self.v = self.v / 2`) in another method keeps the Int64 field and prints 4609434218613702656 — the double's bits. The field pre-pass only ADDS names; a second assignment of a different type is invisible, unlike a LOCAL, which widens across its rebinds."
---

# A field's type is fixed by its first assignment and never widened

- **Type:** bug (Track N — Nil Python frontend) — silent wrong value.
- **Filed:** 2026-08-26 by frank1-N-truediv, found while varying shapes for
  [[bug-n-inferred-return-type-of-true-division-is-int]].

## Repro

```python
class E:
    def __init__(self, n: int):
        self.v = n
    def scale(self):
        self.v = 1.5            # CPython 1.5   pxx 4609434218613702656
        return self.v

class E2:
    def __init__(self, n: int):
        self.v = n
    def scale(self):
        self.v = self.v / 2     # CPython 2.5   pxx 4612811918334230528
        return self.v

print(E(5).scale()); print(E2(5).scale())
```

The `1.5` arm carries no division at all, which is what says this is about
FIELDS and not about `/`.

## Cause

The `self.NAME = ...` pre-pass in `compiler/pyparser.inc` states its own rule in
a comment: *"The scan only ADDS fields, and a name already registered by an
earlier method keeps its first type."* That rule was written to let a field
declared in `__init__` survive being re-assigned in `_build_layout`, and it is
right about IDENTITY. It is wrong about TYPE: the second assignment stores a
double into the Int64 slot the first one sized, with no coercion and no
diagnostic.

A **local** does not behave this way — `PyCollectLocalsAST` unions the types of
every `Syms[]` entry for a name, which is exactly why `n = 5; n = 1.5` is fine
and `self.v = 5; self.v = 1.5` is not. Two spellings of one concept answering
differently is the tell
(`devdocs/dev/normalise-dont-special-case.md`).

## Fix shape

Give the field scan the same widening harvest the local scan has: when a name is
already registered and a later assignment types it differently, widen
(`PyWiden`) rather than keep the first answer. `PyWidenBinding` is probably the
right join — an int field later assigned a float becomes a float; two unrelated
CLASSES already have a decided answer elsewhere (widen to variant, see
`bug-nilpy-local-reassigned-across-classes-keeps-one-static-class`), so reuse
that rule rather than inventing a second one.

Note the ordering hazard: the scan walks methods in source order, so the
harvest has to complete before any field OFFSET is assigned.

## Gate

A `.npy` diffed against CPython: int→float, int→str, and class→other-class
rebinds of one field across two methods; plus the controls that must NOT widen —
a field assigned the same type twice, and a subclass refinement.
