---
track: N
prio: 35
type: bug
summary: "`x in [a, b]` compares boxed handles, so a class's __eq__ is ignored and membership is False for an equal-but-distinct object — the same runtime-dispatch gap as list.sort() ignoring __lt__"
status: done
owner: claude-AN
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

## Fixed (2026-08-08, claude-AN)

`in`, `not in`, `.index()`, `.count()`, `.remove()` and dict keys all match
CPython now. One fix covered all of them because every value comparison in
pylib funnels through `PyVarEq` — the ticket's "check them in the same pass"
turned out to be one site, not six.

### The dispatch already existed

No new machinery: `PyFindDunder` + the class RTTI method table is exactly what
`PyUserObjStr` already uses to reach `__repr__`/`__str__` from a boxed handle.
`PyVarEq`'s VT_OBJECT arm now calls a sibling `PyUserObjEq` after the identity
and container-contents arms, and falls back to the old identity answer when the
class has no usable `__eq__`.

CPython's reflected-`__eq__` rule is approximated: `b.__eq__(a)` is tried when
`a`'s class has no `__eq__` at all. There is no `NotImplemented` here, so the
full protocol is not reproducible.

### TWO __eq__ shapes — and testing one hid the other

Measured with `PXXDBG=a.ir:<Class>.__eq__`:

| written as | `other` arrives as |
| --- | --- |
| `def __eq__(self, other) -> bool` (hand-written, unannotated) | tk=22, `const Variant` |
| `@dataclass`-GENERATED | tk=6, a bare class POINTER |

The first version checked only the Variant shape. Every hand-written case went
green and **every dataclass still compared by handle** — `P(3) in [P(1), P(3)]`
stayed False while `P(3) == P(3)` was True. Both shapes are now dispatched, and
both are in the test.

The class-pointer arm requires the receivers to be the EXACT same class before
calling: the generated body reads fields at fixed offsets, so handing it an
unrelated instance is the same wrong-offset read as
[[bug-nilpy-local-reassigned-across-classes-keeps-one-static-class]]. That is
also what CPython's own dataclass `__eq__` does (`other.__class__ is
self.__class__` → NotImplemented → identity → False), so `P(3) == Q(3)` and
`P(3) == "x"` stay False rather than reading a Q as a P.

### `__hash__` had to follow, or dicts would have silently got WORSE

`PyVarHashKey` hashed an object by its HANDLE. The moment `PyVarEq` started
answering True for distinct-but-equal objects, that broke the invariant its own
comment states — *equal keys MUST hash equal* — and `d[K(1)]` missed the key
`K(1)` had just inserted. So `PyUserObjHash` reads a user `__hash__` (Arity 1,
integer return) the same way.

The blast radius is exactly the classes that define BOTH, because a class with
`__eq__` and no `__hash__` is unhashable in CPython (TypeError) and cannot be a
dict key in a working program at all.

### Verification

- New `test/test_nilpy_membership_eq_dunder.{npy,expected}`, `.expected` from
  CPython: 20 assertions over both `__eq__` shapes, all six comparison sites,
  the no-`__eq__` identity control both ways round, and scalar/tuple/nested/str
  controls. Wired into `test-nilpy`.
- 38 existing `test_nilpy_{dict,dunder,list,set,tuple,dataclass_eq,
  bytes_membership}*` tests re-diffed against CPython: all match. The two that
  differ from a live CPython run (`dict_comprehension`,
  `dict_mutation_during_iteration`) are recorded divergences that match their
  own pinned expectations — checked, not assumed.
- `tools/gate.sh quick` GREEN.

### Left open
[[bug-nilpy-list-sort-ignores-lt-dunder-on-objects]] — the `__lt__` sibling. It
is NOT fixed by this: sorting compares through `pyvar_gt`, not `PyVarEq`, so it
needs the same `PyFindDunder` treatment at that site. This fix is the worked
example for it.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
