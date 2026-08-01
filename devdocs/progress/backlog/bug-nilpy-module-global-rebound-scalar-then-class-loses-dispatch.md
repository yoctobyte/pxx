---
summary: "NilPy: a module global assigned a scalar and LATER a class instance is typed tyVariant, so operator dunders never dispatch on it — no name collision involved"
type: bug
track: N
prio: 65
---

# Rebinding a module global from a scalar to a class kills dunder dispatch

- **Type:** bug (NilPy type inference, silent) — **Track N**
- **Opened:** 2026-08-01. Found while verifying the fix for
  [[bug-nilpy-global-shadowed-by-method-param-name-loses-class-type]] — one of
  that ticket's repros kept failing after the fix, and reducing it showed the
  collision was incidental. This is a third, independent path to the same
  "dunders silently stop dispatching" symptom.

## Repro

No shadowing, no name collision, nothing clever — just two assignments:

```python
other = 0                  # first binding: a scalar

class V:
    def __init__(self, n):
        self.n = n
    def __add__(self, q):
        return "ADD" + str(q.n)

other = V(1)               # second binding: a class instance
p = V(2)
print(other + p)           # CPython ADD2    pxx TypeError: expected a number, got object
```

Delete the `other = 0` line and it works. Both bindings are ordinary Python.

## Cause (to determine — measure, do not guess)

The module widening table unions the types of every module-level binding of a
name, so `tyInt64 ∪ tyClass → tyVariant`, and the global is created as a
variant. A variant operand does not reach compile-time dunder dispatch, which
keys on the operand's static class — so `+` falls through to the numeric path
and raises at runtime.

The widening itself is not obviously wrong (the variable really does hold two
different types over its life). The gap is that **dunder dispatch has no
runtime fallback for a variant that happens to hold a user class at the point
of the operator.** Compare `PyRecIsPylibOwnClass` and the runtime variant
helpers, which already do type checks at run time for the container operators —
this is the same "BOTH-static binop skips the runtime guard" split recorded in
`project_nilpy_static_vs_variant_operand_paths_diverge`, seen from the other
side.

So there are two candidate directions, and which is right is a **design call**,
not something to guess:

1. Make the variant operand path consult the held object's class at run time
   and dispatch the dunder from there (correct for all rebinding shapes, costs
   a runtime check).
2. Narrow the widening so a later class binding wins where the scalar binding
   is dead (fragile, does not fix the genuinely-polymorphic case).

Direction 1 is the one that generalises. If that reading is contested, escalate
as a Track U `decide-*` rather than half-implementing either.

## Impact

Silent and easy to hit: `x = 0` / `x = None` as a module-level "declaration"
followed by a real object later is an extremely common Python idiom, and it
disables every compile-time dunder (arithmetic, ordering, `__eq__`, bitwise,
truthiness) on that name with a `TypeError` far from the cause.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering: scalar-then-class rebinding, `None`-then-class rebinding,
genuinely polymorphic use (both types actually reached at run time), and a
single-binding control.
