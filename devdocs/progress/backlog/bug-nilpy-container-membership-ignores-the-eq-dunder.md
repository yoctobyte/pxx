---
track: N
prio: 35
type: bug
summary: "`x in [a, b]` compares boxed handles, so a class's __eq__ is ignored and membership is False for an equal-but-distinct object — the same runtime-dispatch gap as list.sort() ignoring __lt__"
---

# `x in <list>` ignores `__eq__` — membership by handle, not by value

- **Type:** bug (NilPy, silent wrong answer) — **Track N**
- **Found:** 2026-08-03, gating
  [[bug-nilpy-dataclass-no-generated-eq]]. Confirmed **pre-existing and
  unrelated** to that fix by reproducing with a HAND-WRITTEN `__eq__`.

## Measured

```python
class H:
    def __init__(self, a: int):
        self.a = a

    def __eq__(self, other) -> bool:
        return self.a == other.a


print(H(3) == H(3))            # True on both  -- the bare == dispatches fine
print(H(3) in [H(1), H(3)])    # CPython: True     pxx: False
```

The bare `==` between two statically class-typed operands is correct (that
dispatch lives in `ParseExpr`). Membership goes through pylib's `pycontains`,
which walks the list comparing boxed Variants and never consults the element's
class — so an equal-but-distinct object reports "not in".

Same for a `@dataclass` with the now-generated `__eq__`: `P1(3) in [P1(1),
P1(3)]` is False.

## Family

This is the container-side dunder-dispatch gap, exactly like
[[bug-nilpy-list-sort-ignores-lt-dunder-on-objects]] (`.sort()` never consults
`__lt__`) — one needs `__eq__` from `pycontains`, the other `__lt__` from the
sort comparison, and both are blocked on the same thing: a boxed element has no
static class, and pylib.pas has no visibility into classes the NilPy program
declares later. Worth fixing together, with
[[feature-nilpy-runtime-method-dispatch-on-variant]] as the enabling machinery.

`.index()`, `.count()`, `.remove()` and `dict` key lookup all compare elements
the same way and should be checked in the same pass.

## Why the failure direction matters

Silent, and in the direction that hides: "not found" reads as ordinary absence,
so a membership guard takes the wrong branch with nothing to see. The same
shape as [[bug-nilpy-eq-dunder-ignored]], which was fixed for the expression
path only.

## Gate

A `.npy` diffed against CPython: `in` / `not in` over a list of objects with a
hand-written `__eq__` and over a list of dataclasses, plus `.index()`,
`.count()`, `.remove()` and a dict keyed by such an object, and the existing
expression-path `==` cases still green.
