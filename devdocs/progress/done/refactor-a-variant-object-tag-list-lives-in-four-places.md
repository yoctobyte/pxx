---
track: A
prio: 45
type: refactor
summary: "The set of variant tags whose payload is a refcounted object is written out in FOUR independent places; a tag added to some and not others leaks silently, with RSS as the only symptom. One of them also just zeroes object payloads outright."
status: done
owner: claude-A
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

---

## Done 2026-08-21

### One range, and the emitters got smaller doing it

`VT_OBJ_FIRST` / `VT_OBJ_LAST` in `defs.inc`, mirrored once per builtin unit
(`builtinheap.pas`, `pylib.pas`) with the must-match note, exactly as the ticket
proposed. Three of the four sites now read the same range:

| site | before | after |
| --- | --- | --- |
| `EmitVariantClear` / `EmitVariantRetain` (x86-64, hand-emitted) | four `cmp`/`je` pairs, four patch slots | one `jl` / `jle` pair, one patch slot |
| `PXXVarClear` / `PXXVarRetain` (portable) | `>= 7`/`<= 10` literals | the named bounds |
| `PyVarSlotIsObj` | `(t=7) or (t=8) or (t=9) or (t=10)` | the named bounds |

Tags **11/12/13** (classref, callable, builtin-type) sit above the range and
fall through to the promo test and out — which is what they need, since none of
them owns a heap block. That "what must stay OUT" case is now written next to
the bounds, where the next person adding a tag will actually meet it.

Adding an object tag is now: put it at `VT_OBJ_LAST + 1`, bump the bound, bump
the two mirrors. Four copies of a LIST became four copies of two NUMBERS — which
a reader can diff, which is the whole point; a builtin unit still cannot see
`defs.inc`, so mirrors are unavoidable, not sloppiness.

The x86-64 side is also 26 bytes smaller per emitter and drops two of its
manually-patched jump slots, which is the kind of thing that matters in a
hand-emitted blob: fewer `Patch32` sites is fewer places to mis-order.

### `ClearVariantSlot` — documented, NOT changed

The ticket calls it *"a live suspect, NOT a confirmed bug"*, and that is exactly
where it stays. A fix was written during the parent ticket, measured, found to
change nothing because the routine is not on that path, and reverted. Changing
it now on inspection alone would repeat the failure the parent ticket is famous
for — two "fixed, verified" commits that fixed nothing.

What it got instead is the note it was missing: what the gap is, that it needs a
repro that actually reaches it with a promo-tagged slot that has held an object,
and that `promocore` is a leaf unit which cannot see `builtinheap`, so any fix
has to arrive as a hook (like `PXXObjFinalizeHook`) rather than a call. That is
the difference between a parked question and a forgotten one.

### Verified

- The parent bug's own repro stays flat: the closure-capturing-a-list loop at
  **20 000 and 320 000 iterations both peak at 912 KB**. Before the parent fix
  this slope was 8 MB → 125 MB.
- Tags 11/12/13 still behave: class-as-value, a def in a dict, a bound method,
  `isinstance` against `str` and against a `str` bound to a name, and a def in a
  list — all correct.
- Portable body on a cross target: the same closure loop runs clean on arm32
  (the portable `PXXVarClear` is what every non-x86-64 target uses, so it is the
  half the emitters cannot vouch for).
- `make compiler/pascal26` fixedpoint (1 round) + `tools/gate.sh quick` GREEN.

An aarch64 run was attempted and refused with *"aggregate result with more than
8 params not supported"* — **pre-existing**, reproduced identically with the
v369 `pinned` binary, and already tracked in
[[bug-a-nilpy-on-cross-targets-four-remaining-walls]]. Not caused here.

### Left alone, on purpose

`pylib.pas` has a SECOND tag list — `PyVarIsCallable` (`8, 9, 10, 12`) and the
type-name switch (`9, 10, 12`). Those answer *"is this callable"*, not *"does
this slot own an object"*, and 12 is in one and out of the other precisely
because the two concepts differ. Folding them together would be the opposite of
this ticket. They are a candidate for the same treatment on their own terms, not
part of this one.

## Log
- 2026-08-21 — resolved, commit ac779bf7c.
