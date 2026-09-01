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

## Doing it — and the two traps in the obvious version

**Do NOT extend `FieldIsManaged`.** That is where I first pointed this ticket and
it is wrong: `ClassFieldNeedsFinal` (rtti_emit.inc:56) already carries the
Variant arm and says why it lives THERE and not in the shared predicate —
"extending FieldIsManaged itself would flip records with variant fields into the
managed-record codegen paths, a much broader change than destroy-time finalize."
The class/record divergence is deliberate and documented, not an oversight.

The narrow fix mirrors that precedent one level down: extend **RecordDescMember**
(the descriptor-member predicate) the same way `ClassFieldNeedsFinal` extends its
own, and add the `tyVariant -> 5` arm to the RECORD mKind chain, copying the
CLASS chain's ordering so the array-ness test stays first.

**TRAP: `PXXRecordRetain` HAS NO KIND-5 ARM.** It dispatches kinds 1, 2 and 3
only, and computes `memberSize := SizeOf(Pointer)` for everything that is not a
kind 3 — no 16-byte branch. `PXXRecordRelease` DOES clear kind 5 via
PXXVarClear. So emitting kind-5 record members without adding the retain arm
turns this leak into a DOUBLE FREE on every record COPY, exactly as widening the
dyn-array descriptor stride did in `9cb079528` (reverted by `a584e8fef`) for the
element walks. Add, in the same change:

    else if kind = 5 then memberSize := 16      { in PXXRecordRetain }
    5: PXXVarRetain(itemAddr);                  { its case arm }

A class's Variant field is unaffected by that gap today because a class is
finalized, never copied by value — which is why the asymmetry has been survivable
so far and will stop being survivable the moment records use kind 5.

**Scope the narrow fix honestly.** It reaches a record that is ALREADY managed,
i.e. has a string/array/nested-managed member alongside the Variant. Measured,
dyn array of records, 1000 trips x 8:

    record v: Variant; s: AnsiString   live=7357   <- narrow fix reaches this
    record v: Variant                  live=7708   <- it does NOT

The second stays broken because `RecordHasManagedFields` does not count a
Variant, so the record is not managed at all, `ManagedElemKind` answers 0 for the
element, and no walk is emitted to fix. Closing that one IS the broad change the
`ClassFieldNeedsFinal` comment warns about, and it wants its own ticket and a
full tier rather than being smuggled in here.

**PromoInt needs a new member kind** (7), `memberSize := 16`, with a decref arm
and its retain mirror — and the same trap applies, both halves in one change.
`PXXPromoRetainOne` (builtinheap.pas) exists for the retain half.

**Gate: full tier.** Widening what becomes a record descriptor member changes
record copy and release behaviour corpus-wide, and `gate.sh quick` was GREEN on
the commit that segfaulted `test_promoint_array_cleanup` this morning.

## Why this keeps happening — read this part

Fourth spelling of one policy found in a single day, each missing a different
subset: `ManagedElemKind` (canonical, and it DOES know kinds 5 and 6), the
element walks, the x86-64 inline SetLength retain chains
(`bug-a-x86-64-inline-setlength-never-retains-promo-or-variant-elements`), and
now `FieldIsManaged` plus two divergent mKind chains.

The tempting conclusion is "make `FieldIsManaged` delegate to
`ManagedElemKind` and collapse the two mKind chains into one". That is the
`normalise-dont-special-case` shape and it deletes cases rather than adding
them — but read `ClassFieldNeedsFinal`'s comment first: one of these predicates
feeds DESCRIPTOR EMISSION and the other feeds CODEGEN PATH SELECTION, and they
are deliberately not the same question. Collapsing them is a real design change
with a real blast radius, not a tidy-up. It may still be right; it is not
free, and it is not this ticket.
