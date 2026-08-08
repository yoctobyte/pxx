---
summary: "NilPy: operator dunders NEVER dispatch on a VARIANT operand holding a user class — dispatch is compile-time only. Scalar-then-class rebinding is just one way to get a variant."
type: bug
track: N
prio: 45
blocked-by: [feature-nilpy-runtime-dunder-dispatch-on-variants]
status: done
owner: claude-AN
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

## 2026-08-03 — prio 70 -> 45 with the rest of the runtime-dispatch cluster

Not a re-judgement of this bug: it is the same root cause as
[[decide-nilpy-runtime-dunder-dispatch-strategy]], which the user postponed on
2026-08-03 to study ("we'll get back to this tomorrow"). This ticket's own
summary says so — a rebound global is just one way to end up Variant-held.

Left at 70 it propagated 70 back up the whole chain (blocked-by
[[feature-nilpy-runtime-dunder-dispatch-on-variants]] -> the strategy decision),
so `progress.sh next` kept offering the postponed decision as the global top
pick — which is how it reached an agent today and two days ago. Restore to 70
together with the cluster when the decision is made.

## Fixed (2026-08-09, claude-AN)

The repro matches CPython. The ticket's own summary framed it correctly —
*"dispatch is compile-time only; scalar-then-class rebinding is just one way to
get a variant"* — so the fix is a runtime arm in pylib's variant arithmetic, not
a rule about rebinding.

### Unblocked, not blocked

`blocked-by: feature-nilpy-runtime-dunder-dispatch-on-variants` no longer holds:
that mechanism now exists in `pylib.pas` (`PyFindDunder` over the class RTTI,
added 2026-08-08/09 for `__eq__`, `__hash__`, `__lt__`/`__gt__` and
`__divmod__`). This ticket is the fifth user of it.

### All EIGHT arithmetic entry points, plus ordering

`pyadd_v`, `pysub_v`, `pymul_v`, `pytruediv_v`, `pyfloordiv_v`, `pyfloormod_v`,
`pymod_v`, `pypow_v` each get a user-object arm ahead of their list/str/numeric
arms (so a user class can override even those, matching Python's precedence),
trying the direct dunder then the reflected one.

**Ordering is a separate function and would have been missed by a per-operator
sweep.** `<` goes through `pycmp_v`, which owes a three-way −1/0/1 answer rather
than a boolean, so it asks `__lt__` (or the reflected `__gt__`) first and only
then greater-than. A class declaring just one of the pair still answers, which
matters because Python's ordering protocol only requires `__lt__`. The test's
`lt` line is what catches a fix that stops at the arithmetic ones — it was
failing after the eight arms were wired.

### Typed by RetKind, measured not assumed

Unlike `__eq__`, an arithmetic dunder returns whatever the body returns, so the
call is typed from `mi^.RetKind`. Measured with `PXXDBG=a.ir:<Class>.__add__`
over bodies returning a str, an int, a float, a bool, a list and a mixed pair;
arms exist for each, and an unrecognised kind answers False so the caller keeps
its old behaviour rather than calling through an unchecked ABI. Only the
Variant-`other` parameter shape is accepted — there is no dataclass-GENERATED
arithmetic dunder to produce the class-pointer shape that `__eq__` needed.

### Verification

`test/test_nilpy_variant_operand_arith_dunders.{npy,expected}` (`.expected` from
CPython): all seven operators through a variant operand each with a different
return kind, `<`, the reflected form, the no-dunder TypeError, and controls that
variant scalars/strings/lists are untouched. `gate.sh quick` GREEN. Thirteen
earlier probes from this session (arith, divmod, eq, sort, repr, delitem,
pathlib, class-rebinding) re-diffed against CPython: unchanged.

### Found while gating, filed separately
[[bug-nilpy-block-nested-scalar-then-class-rebind-loses-widening]] — the same
rebinding INSIDE a nested block (`if True:` or `try:`) loses the widening
altogether and adds handles silently. Verified pre-existing against the pinned
binary, so not a regression from this change; it is why this test binds its
no-dunder control at module level.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
