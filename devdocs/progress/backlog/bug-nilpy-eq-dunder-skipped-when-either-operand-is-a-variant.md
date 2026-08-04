---
track: N
prio: 55
type: bug
summary: "`a == b` skips __eq__ and compares identity as soon as ONE operand is a variant (a container element, a for-in variable). Both-static works, so the dunder LOOKS wired up; `a == xs[0]` is silently False."
status: working
owner: claude-AN
---

# `__eq__` is skipped as soon as one operand is a variant

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Found:** 2026-08-04, sizing
  [[bug-nilpy-in-over-objects-ignores-eq]]. It **corrects that ticket's
  premise**, which says "`==` itself now dispatches `__eq__`". It does — but
  only when BOTH operands are statically class-typed.

## Measured (self-hosted binary at HEAD)

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __eq__(self, o) -> bool:
        return self.v == o.v

a = V(1)
b = V(1)
print(a == b)         # True   correct

xs = [V(1)]
e = xs[0]             # e is a VARIANT
print(a == e)         # False  CPython: True
print(a == xs[0])     # False  CPython: True
for q in xs:
    print(a == q)     # False  CPython: True
```

Identical class, identical field, and `a == b` is True while `a == xs[0]` is
False. No diagnostic.

## Why it matters more than the `in` ticket it came from

A container element and a for-in variable are variants, and those are where
objects normally live in Python. So the dunder works in exactly the shape a
minimal test uses (two named locals) and fails in the shape real code uses.
That is also why it went unnoticed while `__eq__` was being wired up.

It is the same cause as the `in` ticket — `__eq__` dispatch resolves against
the operand's STATIC class (parser.inc's comparison arm), and a variant has
none, so the compare falls back to pylib's `PyVarEq`, which compares object
slots by pointer.

## This is what blocks the cheap fix for `in`

Rewriting `x in xs` into a loop over `x == xs[i]` — the obvious frontend-only
fix, needing no runtime hook — **cannot work**, because `x == xs[i]` is exactly
the expression measured False above. Both tickets therefore need the same thing:
a way for `PyVarEq` to reach a user `__eq__` at RUN time. Fixing that fixes `==`,
`in`, `list.count/index/remove` and object dict keys together.

## Fix shape (recon, not started)

`__pxxMethodAddress(Instance, Name)` in `compiler/builtin/builtin.pas` already
walks a class's RTTI method table by name at run time, which is the lookup half.
Two things need checking before building on it:

1. whether a NilPy method carries the `PXX_RTTI_METH_PUBLISHED` flag — that
   routine skips anything that does not, and it is a filter over a table with
   three stride consumers ([[project_rtti_method_table_multi_consumer_stride_landmine]]);
2. the **ABI**, which is the real risk: `__eq__(self, o)`'s second parameter is a
   variant when unannotated and a class pointer when annotated `o: V`, so calling
   the found address through one fixed signature would miscompile half the cases
   — precisely the shape blindspot
   [[project_string_conversion_shape_blindspot_pattern]] describes.

The safe shape is therefore a compiler-emitted **wrapper** of fixed signature
(`function(a, b: TObject): Boolean`) per class that declares `__eq__`, published
under a fixed name that `PyVarEq` looks up — so the marshalling stays where the
types are known and the runtime call has one ABI.

## Gate

A `.npy` diffed against CPython: `==` and `!=` with each operand in turn a
variant (subscript, for-in variable, `.get()` result, function argument); a class
WITHOUT `__eq__` still comparing by identity; `__eq__` annotated `o: V` and
unannotated, both dispatching; and the `in`/`count`/`index`/dict-key consumers
from [[bug-nilpy-in-over-objects-ignores-eq]].


## 2026-08-04 (later) — feasibility probed; it is a FEATURE, not a bugfix

Went at the runtime hook and stopped at the point where it stops being a fix and
becomes compiler work. Three things measured, so the next session does not
re-probe them:

1. **A NilPy method is NOT published in RTTI.** `AddUMethod` sets
   `UMthPub := 0` (`parser.inc`), and the RTTI emitter only sets
   `RTTI_METH_FLAG_PUBLISHED` when `UMthPub = 1`. `__pxxMethodAddress` skips
   every unpublished entry, so it cannot see `__eq__` today even though the
   method table itself holds every method. Publishing dunders specifically would
   be the narrow way in — not publishing everything.
2. **`__pxxMethodAddress` is not reachable from ordinary source** — "undefined
   variable" from a plain program. It lives in `builtin.pas`; whether `pylib`
   may call it is the next thing to check, and it decides whether the lookup can
   live in `PyVarEq` at all.
3. **A method's code ADDRESS is not expressible**: `@TC.eq` gives "cannot call
   non-static method on class type directly". So the cheaper design that avoids
   RTTI — a registry filled at module init with
   `pyeq_register(<class>, @<method>, <param-kind>)`, letting `PyVarEq` pick
   between a variant-taking and an object-taking call shape by a registered flag
   instead of needing a synthesized wrapper — **cannot be written in source
   either**. The frontend would have to emit the address node itself.

So both routes need compiler-side work (publish dunders in RTTI, or emit a
method-address + registration at module init), plus the `PyVarEq` call. That is
a feature-sized Track A+N change with an ABI in the middle, not something to
half-build unattended — the same call the closure-leak ticket's two prior
sessions made about adjacent work.

The design recorded above still looks right; what this adds is that the
`param-kind flag instead of a wrapper` simplification is available and removes
the synthesized-wrapper half, IF the frontend can emit the address. Returned to
`backlog/` with that.
