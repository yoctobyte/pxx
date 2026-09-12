---
slug: feature-n-a-keyword-after-a-star-unpack-at-a-construction-is-still-refused
track: N
prio: 45
type: feature
blocked-by: []
status: backlog
found: 2026-09-12
found-by: frankuser
owner: unassigned
summary: "`Cls(*xs, kw=v)` is still refused with `an argument after *unpacking is not supported yet`, after the same shape was fixed for all three METHOD call sites. Deliberately left: PyClassCreate's argument loop resolves a keyword to a FIELD INDEX (`kwFld := kwPk - 1`), not to the 1-based parameter slot every method path uses, and it carries its own `nArgs`/`kwAny`/`kwExtraHead` bookkeeping that the star expansion does not feed -- so wiring the cap in the same way risks a plausible wrong argument where today it is a clean refusal. The cap mechanism itself already exists and works; only this site's bookkeeping is unwired. One-line change plus whatever `nArgs` needs."
---

# `Cls(*xs, kw=v)` — the constructor arm of the star-follower fix

## What works and what does not

Fixed on 2026-09-12 (`PyStarTrailingKwMinSlot` + a cap in `PyStarExpandCallArgs`):

| shape | site | result |
| --- | --- | --- |
| `f(*xs, kw=v)` free function | `PyStarMixedForwardCall` | worked before |
| `obj.m(*xs, kw=v)` | `PyStarUnpackMethodArgs` | **fixed** |
| `Cls().m(*xs, kw=v)` | `PyParseClassMethodCall` | **fixed** |
| `pick().n(*xs, kw=v)` | `PyParseVariantMethod` | **fixed** |
| `Cls(*xs, kw=v)` | `PyClassCreate` | **still refused** ← this ticket |

CPython accepts all five. `test/test_nilpy_a_keyword_argument_after_a_star_unpack.npy`
covers the four that work and says in its own header not to add a ctor row.

## Why this one was left, and it is not difficulty

The cap is already computed and already correct for this callee — the site passes
a literal `-1` to decline it, with the reason inline. What differs is the
bookkeeping on the other side of the call:

- Every METHOD site resolves a keyword through `PyKwArgIndex`, which answers a
  **1-based parameter slot** and is exactly what the cap is expressed in.
- `PyClassCreate` resolves a keyword to a **field index** (`kwFld := kwPk - 1`),
  falls back to `FindUField` for the dataclass shape, has a third arm for a ctor
  taking `**kwargs` (the key travels as `-(node+1)` on `ASTIVal`), and maintains
  `nArgs`, `kwAny`, `kwExtraHead`/`kwExtraLast` that the star expansion does not
  touch.

So the method fix's shape does not transfer by inspection, and the failure mode
if it is wrong is the one this fix was careful to avoid: an argument that lands
in the wrong slot, at run time, with no diagnostic. A refusal is the better
wrong answer until someone can verify it.

## How to do it

1. Add a ctor row to a differential — `Ctor(*xs, forced=9)` against
   `__init__(self, a, b, forced=0)`, plus the dataclass shape (no `__init__`,
   keyword naming a FIELD) and the `**kwargs` ctor, because those are three
   different arms of the same loop and only the first resembles a method.
2. Pass `PyStarTrailingKwMinSlot(ctorPi)` instead of `-1` at the site, and work
   out what `nArgs` must be afterwards — the expansion appends
   `total - firstSlot` positional args without incrementing it.
3. The positive control is that the pin, and HEAD before the change, refuse it.

## What must stay refused either way

A trailing POSITIONAL (`Cls(*xs, 5)`) and a trailing `**mapping`. Those need the
star's run-time length to know which slot the follower lands on, which a
compile-time expansion does not have — see
`feature-n-a-method-call-cannot-take-an-argument-after-a-star-unpack`, which
keeps that half.
