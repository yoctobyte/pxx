---
type: bug
track: A
prio: 6
summary: FieldIsManaged knows AnsiString, dyn arrays and nested records but not Variant or PromoInt, so a scalar field of either kind is never a descriptor member and its heap payload is never released
tags: [memory-leak, variant, promoint, rtti, records]
---

## What leaks

`rtti_emit.inc:21`:

    function FieldIsManaged(fi: Integer): Boolean;
    begin
      FieldIsManaged := False;
      if UFldTk[fi] = Ord(tyAnsiString) then FieldIsManaged := True
      else if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then FieldIsManaged := True
      else if (UFldTk[fi] = Ord(tyRecord)) and RecordHasManagedFields(...) then ...
    end;

Three kinds. A **Variant** field and a **PromoInt** field are neither, so
`RecordDescMember` excludes them, they never become descriptor members, and
`PXXRecordRetain`/`Release` never see them. The member-kind chain below has the
matching hole — it is `2 / 1 / 4 / else 3`, with no Variant arm and no promo
arm, so anything that DID reach it would be walked as a nested record.

Measured, 2000 trips, `-O2 -dPXX_ALLOC_CENSUS`, local `record p: PromoInt;
s: AnsiString; end`, varying only which member is assigned:

    assign the string only          allocs=19780 frees=19778 live=2      clean
    assign the promo only           allocs=57101 frees=55197 live=1904   LEAK
    assign both                     allocs=72269 frees=70460 live=1809   LEAK
    assign promo an INLINE value    allocs=19780 frees=19778 live=2      clean

The inline-tier row is the control: only a HEAP-tier promo owns an AnsiString
payload, and only that row leaks, so the leaked block is the promo payload and
not the record or the string. Field order does not matter (reversed: same 940).

Same shape for Variant, in a dyn array of such records: `live=7822` over 1000
trips of 8 elements, against `live=4` for the string-only control.

**A record with ONLY a promo field measures clean** (`live=6`) — with no managed
field at all the record never becomes managed and something else reclaims it.
So the bug needs a second, recognised managed member to appear, which is why it
hid: the obvious one-field probe says everything is fine.

## The two halves are NOT the same size

**Variant is a compiler-side fix only.** The runtime is already complete:
`PXXRecordRelease` has `kind = 5` with `memberSize := 16` and dispatches to
`PXXVarClear`, and `PXXRecordRetain` mirrors it. Nothing emits kind 5 for a
scalar Variant field. Teach `FieldIsManaged` about `tyVariant` and add
`else if UFldTk[fi] = Ord(tyVariant) then mKind := 5` to the chain — ordered
BEFORE the array test only if you have checked the array-ness hazard the big
comment above that chain documents.

**PromoInt needs a new member kind.** There is no promo kind in the record walk
(1 String, 2 DynArray, 3 Record, 4 interface, 5 Variant, 6 NilPy binding), so it
needs a kind 7 with `memberSize := 16` and a decref/incref pair —
`PXXPromoRetainOne` already exists for the retain half.

Do the CLASS layout descriptor at the same time; it shares `FieldIsManaged` and
therefore the same hole for a scalar Variant or promo field of a class.

## Why this keeps happening

Fourth spelling of one policy found in a day, each missing a different subset:
`ManagedElemKind` (the canonical one, which DOES know kinds 5 and 6), the
element walks, the x86-64 inline SetLength retain chains
(`bug-a-x86-64-inline-setlength-never-retains-promo-or-variant-elements`), and
now `FieldIsManaged`. Worth asking on this one whether `FieldIsManaged` can
simply DELEGATE to `ManagedElemKind` rather than re-answer the question — that
is the `normalise-dont-special-case` fix, and it deletes a case rather than
adding two.
