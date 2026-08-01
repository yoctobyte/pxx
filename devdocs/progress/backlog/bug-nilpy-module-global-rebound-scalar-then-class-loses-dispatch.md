---
summary: "NilPy: operator dunders NEVER dispatch on a VARIANT operand holding a user class — dispatch is compile-time only. Scalar-then-class rebinding is just one way to get a variant."
type: bug
track: N
prio: 70
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

## 2026-08-01 — scope CORRECTED and widened: it is not about rebinding

Measured, and the original framing (mine) was too narrow. Rebinding is merely
one way to end up with a variant; the actual rule is:

> **Operator dunders never dispatch on a VARIANT operand, whatever put the class
> in it.**

No rebinding, no collision, both operands variants holding the same user class:

```python
class V:
    def __init__(self, n): self.n = n
    def __add__(self, q): return "ADD" + str(q.n)

box = [V(1), V(2)]
a, b = box[0], box[1]
print(a + b)          # CPython ADD2   pxx TypeError: expected a number, got object
```

So `x = 0; x = V()` is one entry point; unpacking from a container, a variant
field read, a variant-typed parameter and an unannotated def return are others.
Retitled and re-prioritised accordingly (65 → 70): the surface is much larger
than "an odd rebinding pattern".

## Why this is FEATURE-sized, not a bug fix

Dunder dispatch is **entirely compile-time**: `ir.inc` keys on the operand's
static class (`IRNodePyListRec` and friends) and emits a direct call. There is
no runtime path, and pylib has no by-name method dispatch to borrow —
`pydynattr_get/set/has` resolve ATTRIBUTES, not method calls with arguments, so
they cannot stand in for it.

Making a variant operand dispatch therefore needs one of:

1. **A runtime dunder dispatcher.** Given a boxed object, find `__add__` on its
   actual class and call it. pxx has RTTI method reflection (the VMT-8 table),
   so the lookup is feasible — but it needs an argument-passing convention and a
   Variant-returning shim per dunder, and it puts a reflective call on an
   arithmetic path.
2. **A compile-time guarded dispatch.** Where a variant *might* hold a class,
   emit `if tag = VT_OBJECT and class-has-__add__ then <dispatch> else
   <numeric>`. Avoids reflection but needs the candidate class set, which is
   exactly what the variant erased.
3. **Narrow the widening** so these names stay `tyClass`. Fixes the rebinding
   entry point only, and does nothing for containers or variant parameters —
   the majority of the surface.

Route 1 generalises; route 2 is cheaper but partial; route 3 does not address
the corrected scope at all.

**This wants a Track U decision before implementation** — it is a design choice
about how far NilPy's dynamic dispatch goes, with a real cost on the arithmetic
path, not something to pick while working a bug queue. Not filed as `decide-*`
yet only because the recommendation (route 1) is clear; if that is contested,
split it.

Left claimed but NOT implemented tonight, deliberately: improvising a reflective
dispatch path at this size is how a plausible-but-wrong design gets baked in.
