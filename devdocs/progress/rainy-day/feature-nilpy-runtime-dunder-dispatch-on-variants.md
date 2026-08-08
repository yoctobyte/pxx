---
track: N
prio: 45
type: feature
blocked-by: [decide-nilpy-runtime-dunder-dispatch-strategy]
---

# Runtime dunder dispatch for a user class held in a Variant

- **Type:** feature (NilPy dynamic dispatch) — **Track N**
- **Opened:** 2026-08-01, consolidating THREE tickets that were being worked as
  separate bugs and turn out to share one root.

## The shared root

Dunder dispatch in pxx is **entirely compile-time**: `ir.inc` keys on the
operand's STATIC class (`IRNodePyListRec` and friends, `PyClassTruthyDunder`,
the ordering/bitwise arms) and emits a direct call. There is no runtime path at
all, and pylib has nothing to borrow — `pydynattr_get/set/has` resolve
ATTRIBUTES, not method calls with arguments.

So the moment a user-class instance is reached through a **Variant**, every
dunder stops working. All three of these are that one fact:

| ticket | how the Variant appears | symptom |
| --- | --- | --- |
| [[bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch]] | a global bound to two types widens to Variant | `a + b` raises TypeError |
| [[bug-nilpy-dunders-not-dispatched-through-containers]] | containers hold Variants | `[a, b]` prints `[, ]`; `sorted()` raises |
| [[feature-nilpy-arithmetic-ordering-dunders]] | the umbrella for the operator set | the compile-time half is largely done |

Measured 2026-08-01, one binary, all three shapes:

```python
a, b = C(1), C(2)
str(a)          # S1        — direct, works
a < b           # True      — direct, works
[a, b]          # [, ]      — CPython [C1, C2]
str([a][0])     # ""        — CPython S1
sorted([b, a])  # TypeError — CPython [C1, C2]

box = [V(1), V(2)]              # no rebinding, no collision
box[0] + box[1]                 # TypeError — CPython ADD2
```

Fixing any one of them in isolation means building a private runtime path that
the other two would then duplicate — which is exactly how the `not <x>` family
came to need three separate fixes (see `PyClassTruthyDunder`'s comment). Hence
this umbrella.

## Design options

1. **A runtime dunder dispatcher.** Given a boxed object, find `__add__` /
   `__repr__` / `__lt__` on its ACTUAL class and call it. pxx has RTTI method
   reflection (the VMT-8 table), so lookup is feasible — but it needs an
   argument-passing convention, a Variant-returning shim per dunder, and it puts
   a reflective call on the arithmetic and repr paths.
2. **Compile-time guarded dispatch.** Where a Variant *might* hold a class, emit
   `if tag = VT_OBJECT and class-has-__add__ then <dispatch> else <today>`.
   Avoids reflection, but needs the candidate class set — which is precisely
   what the Variant erased.
3. **A per-class dunder table registered at construction**, so pylib can look up
   a function pointer by (class, dunder) without full reflection. A middle road:
   no reflection on the hot path, no need for the static candidate set, at the
   cost of a table and its registration.

Route 1 generalises; route 3 is probably the better engineering trade; route 2
does not cover the container case at all, which is the most visible one.

## This wants a Track U decision first

It is a design choice about how far NilPy's dynamic dispatch goes, with a real
cost on hot paths, and it is the kind of thing that is very expensive to redo.
Not something to pick while working a bug queue — see
[[decide-nilpy-runtime-dunder-dispatch-strategy]].

## Gate

A `.npy` diffed against CPython covering, for one class defining
`__repr__`/`__str__`/`__lt__`/`__add__`: direct use, use through a list, `str()`
of an element, `sorted()`, a Variant-typed global from scalar-then-class
rebinding, and a Variant-typed parameter — all matching CPython, with the
compile-time static paths unchanged.

## 2026-08-08 — scoped to option B and PARKED to rainy-day

[[decide-nilpy-runtime-dunder-dispatch-strategy]] is decided: **option B**,
compile-time guarded dispatch. No reflective RTTI walk — the compiler generates
a switch on class identity and installs it where the runtime needs it, the way
`PXXObjFinalizeHook` is installed.

Deliberately NOT scheduled ("park this issue to postponed", user). Two things to
carry into whoever restarts it:

- **Do not halt on several candidate classes.** That is ordinary polymorphic
  Python and is exactly what the switch handles. Hard-fail only when NO class
  declares the dunder.
- **The cheapest real win is not this ticket.** pylib's container renderer has
  no route to dispatch that already works today (measured 2026-08-07). That is a
  hook, and it removes most of the visible symptom
  ([[bug-nilpy-list-of-custom-objects-loses-repr-str]]) without building a
  dispatcher at all.
