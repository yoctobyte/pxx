---
track: A
prio: 45
type: refactor
summary: "The set of variant tags whose payload is a refcounted object is written out in FOUR independent places; a tag added to some and not others leaks silently, with RSS as the only symptom. One of them also just zeroes object payloads outright."
---

# One concept, four copies: which variant tags carry a refcounted object

## The four

| site | form | tags it knows |
| --- | --- | --- |
| `EmitVariantClear` / `EmitVariantRetain`, `compiler/ir_codegen.inc` | hand-emitted x86-64 | 7, 8, 9, 10 |
| `PXXVarClear` / `PXXVarRetain`, `compiler/builtin/builtinheap.pas` | portable Pascal | 7, 8, 9, 10 |
| `PyVarSlotIsObj`, `compiler/builtin/pylib.pas` | Pascal predicate | 7, 8, 9, 10 |
| `ClearVariantSlot`, `compiler/builtin/promocore.pas` | Pascal | **none — see below** |

They agree today only because
[[bug-nilpy-bound-fn-closure-objects-are-never-freed]] just went through and
made them agree. Nothing keeps them in step.

## Why this is worth a ticket rather than a comment

**The failure is silent and the only symptom is RSS.** A tag added to the
emitters and missed in the portable twin does not crash, does not produce a
wrong value, and does not fail any test in the suite — the slot is simply never
released. That is exactly how the parent bug survived four investigation rounds:
`VT_BOUNDFN_TAG` was added to the emitters, the object was given a refcount, and
the leak persisted because `PXXVarClear` — the routine that prepares the
hidden-destination temp of a variant-returning call, once per loop iteration —
still tested `7, 8, 9`. Two earlier sessions committed "fixed, verified" changes
that did not move the slope for want of the fourth copy.

The same file's own history has the prior instance: `PXXVarClear`'s comment
records that the portable body "previously missed" the promo-tag range, "a
cross-target leak". Same routine, same class of omission, twice.

## `ClearVariantSlot` is a live suspect, NOT a confirmed bug

`promocore.pas`'s `ClearVariantSlot` releases a `VT_STRING`/promo payload and
otherwise just zeroes the slot — so an object payload passing through it is
dropped without a release. A fix was written during the parent ticket, measured,
found to change nothing on that repro (the routine is not on that path), and
**reverted rather than shipped**, because an unmeasured change to a shared
runtime clear path is how that ticket accumulated its wrong fixes.

It still looks wrong by inspection. It needs a repro that actually reaches it —
a promo-tagged variant slot that has held an object — before anything is
changed. Note `promocore` is a leaf unit and cannot see `builtinheap`, so the
release would have to arrive as a hook, the way `PXXObjFinalizeHook` already
does.

## Shape of a fix

Make it one list. The tags are contiguous (7..10) and the emitters already
range-test the promo block, so the honest version is a single named range —
`VT_OBJ_FIRST` / `VT_OBJ_LAST` in `defs.inc`, mirrored once per builtin unit
(builtin units cannot see `defs.inc`, so a mirror is unavoidable — but ONE
mirror per unit, with the "must match defs.inc" note, beats four ad-hoc lists).
Then adding a tag is one edit plus a range bump, and a missed site becomes a
compile-time absence rather than a silent leak.

`devdocs/dev/normalise-dont-special-case.md` is the governing note: when a
construct is reachable through several shapes, normalise rather than growing a
second path, "because the second path is the one that stays broken."

## Gate

Self-host fixedpoint byte-identical + `tools/gate.sh quick`; the closure and
object-reclamation RSS repros in the parent ticket stay flat; cross targets,
since the portable body is what the non-x86-64 backends use.
