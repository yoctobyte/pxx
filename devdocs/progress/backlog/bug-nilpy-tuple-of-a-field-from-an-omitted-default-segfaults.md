---
prio: 65
type: bug
track: N
summary: "SEGFAULT: a field assigned from an OMITTED defaulted variant ctor parameter, returned inside a TUPLE, crashes. Needs all four — a constructor, the default actually taken, the field, and the tuple; drop any one and it works."
---

# A tuple holding a field that came from an omitted default segfaults

- **Type:** bug (NilPy, hard crash) — **Track N**
- **Found:** 2026-08-04, Track A+N overnight, regression-testing the
  constructor-default fix
  ([[bug-nilpy-constructor-parameter-defaults-are-ignored]]).
- **PRE-EXISTING**, verified against `stable_linux_amd64/default/pinned` and
  against HEAD `a87e8a224` — it is neither caused nor fixed by that work.

## Repro

```python
class A:
    def __init__(self, a, on_change=None):
        self.a = a
        self.oc = on_change
    def show(self):
        return (self.a, self.oc)
print(A(1).show())
```

```
CPython:  (1, None)
pxx:      Segmentation fault (core dumped)
```

## Narrowing — it needs all FOUR conditions

Each row drops exactly one and passes:

| variation | result |
| --- | --- |
| the repro above | **SIGSEGV** |
| explicit argument: `A(1, 2).show()` | ok — `(1, 2)` |
| no tuple: `return self.oc` | ok — `None` |
| plain function, not a method: `def g(a, oc=None): return (1, oc)` | ok — `(1, None)` |
| field set from a LITERAL: `self.oc = None` in a no-arg `__init__` | ok — `(1, None)` |
| field read directly: `print(A(1).oc)` | ok — `None` |
| field returned alone: `return self.a` | ok |

So: a CONSTRUCTOR, whose defaulted VARIANT parameter is actually OMITTED, whose
value is stored in a FIELD, and that field is then returned inside a TUPLE.

## Why it is worth its own ticket

The shape is ordinary and common — an optional callback or option stored on the
instance, later returned as part of a pair — and it is a hard crash rather than a
wrong value, so it will stop a program dead rather than corrupt it quietly. It is
also exactly the shape the constructor default-fill code carries a comment about:

> `def __init__(self, a, on_change=None)` types on_change Any, and filling it
> with AN_INT_LIT 0 handed the callee a machine word where it reads a 16-byte
> slot — the call SEGFAULTED

That comment describes a fix that WAS made (fill with `pynone()` rather than an
ordinal), and the direct read now works, so the remaining crash is downstream of
the fill, not in it. `PyMakeTupleFrom` builds a TPyList, so the suspect is how a
variant FIELD holding None is copied into the tuple's element slot — compare
against the literal-None field case, which works, and the plain-function case,
which also works.

## Gate

`make test-nilpy` + self-host byte-identical. A `.npy` diffed against CPython
carrying the repro plus the six narrowing rows above, so whichever of the four
conditions is actually responsible stays pinned once it is fixed.
