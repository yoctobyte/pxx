---
type: bug
track: A
prio: 6
summary: a PromoInt field has no record/class member kind at all so it leaks everywhere, and a Variant field leaks specifically through the RECORD descriptor because that chain lacks the Variant arm the CLASS chain has
tags: [memory-leak, variant, promoint, rtti, records]
---

## Measured first — the two bugs have different shapes

2000 trips (dyn-array rows 1000 x 8), `-O2 -dPXX_ALLOC_CENSUS`, live blocks:

    shape                                        Variant field   PromoInt field
    local record, field is the ONLY member       clean            clean (6)
    local record, + an AnsiString member         clean (2)        LEAK (1904)
    record inside a dyn array                    LEAK (7822)      LEAK (7685)
    class field, + an AnsiString member          clean (1)        LEAK (1787)

Controls: the string-only record and string-only class are clean (2 and 1), and
a promo field assigned an INLINE value is clean — only the HEAP tier owns an
AnsiString payload, so that row identifies the leaked block as the promo payload
rather than the record or the string.

**PromoInt leaks in every shape that has a second managed member.** There is no
promo member kind anywhere: the record walk knows 1 String, 2 DynArray, 3
Record, 4 interface, 5 Variant, 6 NilPy binding, and nothing for a promo slot.

**Variant leaks only through the RECORD descriptor.** The local record and the
class are both clean, because a class layout descriptor's chain HAS the arm:

    rtti_emit.inc, CLASS layout (~1510)      RECORD layout (~1371)
      dyn array -> 2                           dyn array -> 2
      tyAnsiString -> 1                        tyAnsiString -> 1
      COM interface -> 4                       COM interface -> 4
      tyVariant -> 5            <-- MISSING    (none)
      tyClass -> 6              <-- MISSING    (none)
      else -> 3                                else -> 3

Two writers for one question, and they disagree. A Variant record member falls
to `else -> 3` and is walked as a NESTED RECORD with a typeRef that is not one.

`FieldIsManaged` (rtti_emit.inc:21) has the matching hole and gates both, via
`RecordDescMember`: it recognises AnsiString, dyn arrays and nested
records-with-managed-fields, and neither Variant nor promo. So for the record
path the member is not even emitted.

**A field of either kind ALONE measures clean**, which is why this hid: with no
recognised managed member the record never becomes managed and something else
reclaims it. It takes a second, recognised member to expose the gap — the
obvious one-field probe reports success.

## Doing it

**Variant is compiler-side only.** The runtime is already complete:
`PXXRecordRelease` has `kind = 5` with `memberSize := 16` dispatching to
`PXXVarClear`, and `PXXRecordRetain` mirrors it. Add `tyVariant` to
`FieldIsManaged` and the `mKind := 5` arm to the RECORD chain — the class chain
is the worked example. Mind the array-ness hazard the long comment above that
chain documents: `UFldTk` of an array field is its ELEMENT type, so the dyn-array
test must stay first.

**PromoInt needs a new member kind** (7), `memberSize := 16`, with a decref arm
and its retain mirror. `PXXPromoRetainOne` (builtinheap.pas) already exists for
the retain half.

## Why this keeps happening — read this part

Fourth spelling of one policy found in a single day, each missing a different
subset: `ManagedElemKind` (canonical, and it DOES know kinds 5 and 6), the
element walks, the x86-64 inline SetLength retain chains
(`bug-a-x86-64-inline-setlength-never-retains-promo-or-variant-elements`), and
now `FieldIsManaged` plus two divergent mKind chains.

So the fix worth doing is not two more arms. It is making `FieldIsManaged`
DELEGATE to `ManagedElemKind`, and collapsing the record and class mKind chains
into one — `normalise-dont-special-case`, and it deletes cases instead of adding
them. Adding the arms by hand makes this the fifth and sixth copy.
