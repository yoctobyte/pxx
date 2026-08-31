---
track: N
prio: 45
type: feature
summary: "hasattr reports True for a field the instance never assigned — `if flag: self.m = 1` then hasattr(a,\"m\") on a False path answers True where CPython answers False. The remaining half of the DECIDED decide-nilpy-hasattr-per-instance-semantics: the per-instance assigned bit."
---

# `hasattr`: the per-instance "assigned" bit

- **Type:** feature (implements a resolved decision) — **Track N**
- **Opened:** 2026-08-07, splitting out the half NOT covered by
  [[bug-nilpy-hasattr-on-a-variant-receiver-always-answers-false]].

## Measured (self-hosted, after that bug's fix)

```python
class A:
    def __init__(self, flag):
        if flag:
            self.m = 1
a = A(False)
print(hasattr(a, "m"))        # CPython False   pxx True
box = [a]
print(hasattr(box[0], "m"))   # CPython False   pxx True
```

NilPy fields always exist and are zero-initialised, so "declared" and "assigned"
are the same thing to the compiler and different things to Python. A field
assigned on only SOME path through `__init__` is the shape that separates them.

A bare class-level annotation is NOT this shape — `n: int` with no assignment
already answers False on both sides, measured, so the divergence is specifically
about *conditional* assignment.

## Relationship to the variant-receiver fix

That fix made the **declared-field** half answerable for a receiver whose class
is a run-time fact, by testing the object's class against the set that declares
the name. It deliberately did **not** attempt the assigned bit.

Worth stating plainly, because it is a trade rather than a pure win: before that
fix a variant receiver answered `False` *always*, which was wrong for the common
case (a field assigned in `__init__`) and right for this conditional case **by
coincidence**. After it, a static and a variant receiver give the SAME answer —
`True` — so this case went from accidentally-right to consistently-wrong. That
is the better place to be: the remaining defect is now ONE bug with one cause
instead of two answers that disagreed with each other, and this ticket is it.

## The design is already decided

[[decide-nilpy-hasattr-per-instance-semantics]] — user, 2026-08-01, option 2:
real per-instance "assigned" tracking, scoped by whole-program usage analysis so
only what a `hasattr` site can actually reach pays anything.

1. Enumerate every `hasattr(obj, name)` call site.
2. Resolve `obj`'s static class per site; an ambiguous target (a Variant, a
   base-typed value with several subclasses) falls back to the whole ambiguity
   set. **The variant-receiver fix already computes exactly this set** — see
   `PyHasAttrClassChain` — so step 2's machinery exists.
3. Resolve `name` per site. A literal scopes tracking to one field; `hasattr`
   currently *requires* a literal, so the non-constant fallback is unreachable
   today.
4. Only classes/fields reached by 2+3 get a per-instance assigned bit and the
   extra write at assignment. Everything else keeps today's exact codegen.

`hasattr` is rare (4 sites in the current corpus), so most programs pay nothing.

## Fix shape

The bit itself is the new part: one bit per (class, tracked field) in the
instance, cleared by the existing zero-init and set at every assignment to that
field. Then `hasattr` reads the bit instead of answering from the class alone —
for a static receiver directly, and for a variant receiver as the second half of
the class test the chain already emits.

## Gate

Per-fix loop. Extend `test/test_nilpy_hasattr_variant_receiver.npy` (which
already carries the class-test half and every erased receiver route) with:
conditional assignment in `__init__` on both paths, assignment after
construction, a field assigned in a method rather than `__init__`, and both a
static and a variant receiver for each — diffed against CPython. Plus the
zero-cost check the decision asks for: a class reached by no `hasattr` call site
compiles identically to today.
