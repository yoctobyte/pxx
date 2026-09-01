---
type: bug
track: A
prio: 6
summary: x86-64 inlines SetLength and its retain chain stops at kind 4, so promo and variant array elements are never retained — which is why the descriptor stride for kinds 5/6 cannot be emitted
tags: [O, memory-leak, promoint, variant, dynarray]
---

## The fork in the road

Every cross backend calls `PXXDynSetLen` (builtinheap.pas ~4353), which reads
`baseKind` from the descriptor and has correct retain AND release arms for all
of kinds 1/3/4/5/6. **x86-64 does not call it** — it inlines the whole of
SetLength in `ir_codegen.inc` at `IR_SETLEN_DYN` (~10592), and that inline
retain chain is:

    if slDepth > 1      -> retain sub-array handle
    else if slMek = 1   -> AnsiString incref
    else if slMek = 4   -> PXXIntfAddRef
    else                -> assume RECORD: EmitManagedRecordIntfWalk + Retain

Kinds **5 (promotable int)** and **6 (Variant)** fall into that final unguarded
`else` and are handed to `EmitManagedRecordRetain`, whose first line is
`if recId < REC_UCLASS_BASE then Exit` — and their recId is REC_NONE. So they
get **no retain at all**. The release emitted immediately afterwards is
`PXXDynArrayRelease`, which *does* have kind 5 and 6 arms.

This is the ninth site of the `ManagedElemKind` policy, and it missed a case —
exactly what that function's own header predicts of every copy of it.

## Why it currently only leaks

The asymmetry is invisible today because the anon dyn-array descriptor writes
`baseTypeRef = 0` for kinds 5/6, so the release half reads a stride of zero and
its `elSize > 0` guard declines too. Both halves decline: **balanced, and leaky.**

`9cb079528` widened that descriptor arm to emit the real stride, which woke the
release half **alone** — release without its retain — and turned the leak into a
double free. Measured: `test_promoint_array_cleanup` exit 139 with the widening,
exit 0 / `39000/39000` without. `a584e8fef` reverted the widening and recorded
the pairing requirement in `rtti_emit.inc`.

So the two changes are correct only **together**, and this ticket is the half
that has to land first.

## The leak that is open right now

    local `array of PromoInt`, heap-tier payloads, 1500 trips
      allocs=12347 frees=1371 live=10976      (measured both with and without
                                               the widening — this path never
                                               retained OR released)

    local `array of Variant`, 1500 trips
      allocs=4274 frees=1424 live=2850

## Exactly which cells leak — the matrix

4 element kinds x 4 container shapes, 1000 trips of 8 elements each, one
program per cell, `-O2 -dPXX_ALLOC_CENSUS`, live blocks at exit:

    element kind      local dyn   local fixed   record field   nested dyn
    AnsiString                4             3              4            5
    record + string           4             3              4            5
    PromoInt               7820            11             12         7805
    Variant                7708             3              4         7805

Read it as three facts:

- The leak is **kinds 5 and 6 in a DYNAMIC array only**. Two of four kinds, two
  of four shapes. Everything else reclaims.
- **Fixed arrays are clean** for promo and variant, so the element walk itself
  and ManagedElemKind's kind 5/6 answers are right — this is the dyn-array
  path alone, which is what points at the inline SetLength rather than at the
  policy.
- **Record fields are clean** for promo and variant, which is `2b70ff387` +
  `9cb079528`'s descriptor-writer half doing its job. That half was KEPT when
  `a584e8fef` reverted the stride; this row is the evidence it earns its place.

`nested dyn` (`array of array of T`) leaks at the same rate, so the depth>1 arm
needs the same treatment and is not covered by fixing the leaf case alone.

Use this table as the acceptance test: every cell must land in single digits.

## The sibling — fix it in the SAME change

`ir_codegen.inc` ~9889 (the copy-prefix retain on the symbol SetLength path)
has the identical `1 / 4 / else-assume-record` chain, **plus** a stride bug the
first site does not have: it advances

    if slMek = 3 then RecSize(...) else 8

and kinds 5 and 6 are **16-byte** slots on x86-64 (PromoInt64 = tag+payload,
Variant = tag+payload). That stride is latent only because the record walk it
emits is inert for a REC_NONE id — the loop strides wrong and does nothing.
**Add the arms there without fixing the stride and the new retain walks half
elements.**

## Doing it

Add `slMek = 5` and `slMek = 6` arms at both sites. The runtime halves already
exist and are the definition to mirror — `PXXDynArrayRetainImmediate`'s kind-5
and kind-6 arms (builtinheap.pas ~3769/~3790): kind 5 is
`if tag = PROMO_TAG_HEAP then PXXStrIncRef(payload)`, kind 6 is `PXXVarRetain`
(single argument, so its call shape is simpler than the kind-4 arm's). Consider
calling `PXXDynArrayRetainImmediate` once per element instead of hand-rolling
the arms a tenth time — one call, and it cannot drift from the release side.

Then re-widen the `rtti_emit.inc` arm (the comment there names this ticket).

**Gate: full tier, not quick.** `gate.sh quick` was GREEN on the broken commit;
only `--tier full` caught it, as `test-core#244`.
