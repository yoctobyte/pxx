---
type: bug
track: A
prio: 6
summary: FIXED across four commits — a Variant or promo FIELD of a record or class is now a descriptor member, scalar and fixed-array alike, and a record whose only managed members are of those kinds is now a managed record; every shape measured clean (was 1904-11398 leaked per 1000 trips)
tags: [memory-leak, variant, promoint, rtti, records]
status: done
---

## Status

The **Variant half is fixed** in `b2997a31b` (RecordDescMember + the RECORD
`tyVariant -> 5` arm, with PXXRecordRetain's missing kind-5 arm in the same
commit): live=11658 -> 6, regression test `test_record_variant_member_leaks`.

The **PromoInt half is fixed** in `f806993c8` as **member kind 7**, in both
descriptor chains, `RecordDescMember` and `ClassFieldNeedsFinal`, with
retain/release/zero arms in builtinheap. Regression test
`test_record_promo_member_leaks`. Measured, live blocks over 2000 trips:

    local record {promo, string}   1904 -> 6      class field    1787 -> 7
    dyn array of that record       7685 -> 21     array[0..7]    7578 -> 18

**NOTHING REMAINS OPEN. All four shapes are fixed** — see "Closed out" at the
end for the final tally. The section below is the history of the last one.

Formerly open:

- **A record whose ONLY member is a Variant, INSIDE A DYN ARRAY** (live=7708).
  `RecordHasManagedFieldsDepth2` counts AnsiString, dyn-array, COM-interface and
  nested-record fields, and neither a Variant nor a promo, so such a record is
  not a managed record and a dyn-array element release never walks it.

  **NAME THE CONTAINER, because three neighbouring shapes are clean and one of
  them is the obvious probe.** Measured at 1000 trips:

      record{v:Variant}          plain local          live=2      clean
      record{v:Variant}          class field          live=1      clean
      record{v:Variant; s:Str}   in a dyn array       live=5      clean
      record{v:Variant}          in a dyn array       live=7708   LEAK

  A plain local is clean because a local is finalized by its own scope-exit
  path, which knows a Variant directly; only the DYN ARRAY element goes through
  the record descriptor, and only the record descriptor consults this gate.
  Adding any second managed member flips the gate and the leak vanishes — which
  is why the row above it reads clean and why a one-field probe reports success.
  An earlier revision of this ticket said "a record whose ONLY member is a
  Variant (live=7708)" with no container, while its own matrix said that shape
  was clean; both halves were measurements of DIFFERENT shapes filed as one.

  The walk machinery is now complete — `PXXRecordRetain`/`Release`/`ZeroManaged`
  have kind-5 arms since `b2997a31b` and kind-7 arms since `f806993c8`, and
  `RecordDescMember` describes both. **This gate is the last missing piece**,
  and it is the broad change `ClassFieldNeedsFinal` warns about: flipping the
  gate changes copy, zero-init and finalization together, the exact
  one-predicate-answers-three-questions shape that the interface-field history
  in `RecordHasManagedFieldsDepth2` records as having gone wrong before.
  Note the promo fix does NOT reach it and was never going to: the same
  single-member row for promo measured clean at 6 both before and after, because
  with no second managed member the record is not managed and there is no walk
  for a member kind to appear in. Describing the member is downstream of the
  record being walked at all.

### Not covered by the promo fix, deliberately

**An `array[0..N] of PromoInt` MEMBER.** Both new arms are scalar-only
(`... and not UFldIsArray[fi]`), matching the existing variant arm exactly
rather than widening two mechanisms in one change. A fixed array OF records that
each hold a scalar promo IS covered and is measured above (7578 -> 18); the
uncovered shape is the array being the promo itself.

### Kind 7 is the only member kind carrying a stride

Its `typeRef` word holds `TypeSlotSize`, because `PromoInt` is not one type: it
resolves through `PromoIntDefaultKind` to `tyPromoInt64` (16 bytes) on a 64-bit
target and `tyPromoInt32` (8) on a 32-bit one, and the numbered spellings are
REFUSED on the target they do not match. A runtime constant would be right on
half the fleet. Verified by reading emitted descriptor bytes on five targets
(16 on x86-64/aarch64, 8 on i386/arm32/riscv32), with a promo-free program as
the scanner's negative control.

### The retain arm was the half that could have shipped broken

Describing the member makes `PXXRecordRelease` release it; a release without a
matching retain does not leak, it DESTROYS SetLength survivors — the pairing
failure that made `9cb079528` segfault master (reverted as `a584e8fef`). Proven
rather than assumed: with only the retain arm removed and the compiler rebuilt,
the new test reports **3/6000** and the `-dPXX_HEAP_DEBUG` build exits **139**.

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


## Closed out (2026-09-01)

Four commits, each a different predicate, all of them saying "this field is not
worth walking" for a different reason:

    b2997a31b  RECORD descriptor never described a Variant member (kind 5)
    f806993c8  a promo member had NO member kind at all (kind 7, + stride)
    a544cab70  RecordHasManagedFieldsDepth2 counted neither, so a record whose
               managed members were ALL of those kinds was never WALKED
    2859efe06  the membership arms excluded FIXED ARRAYS of either

Final tally, live blocks per 1000 trips:

    local record {promo, string}                      1904 ->  6
    class field {promo, string}                       1787 ->  7
    dyn array of record with a promo member           7685 -> 21
    record{v:Variant} in a dyn array                  7708 ->  4
    record{p:PromoInt} in a dyn array                 7791 ->  7
    record{v:Variant} nested in a managed record       936 ->  1
    array[0..3] of Variant as a member                3799 ->  3
    array[0..3] of PromoInt as a member               3860 ->  8
    array[0..3] of Variant, in a dyn array           11398 -> 10
    array[0..3] of PromoInt, in a dyn array          11110 -> 10

### What this family was actually about

**Four predicates, one concept, disagreeing.** `FieldIsManaged`,
`RecordDescMember`, `ClassFieldNeedsFinal` and `RecordHasManagedFieldsDepth2`
all answer some version of "does this field need managing", and each was written
for its own caller. A field could satisfy one and fail another, and every leak
here is a field that fell into a gap between two of them. Two of the fixes point
in OPPOSITE directions — a544cab70 because a record was not managed enough for
anything to walk it, 2859efe06 because a record became managed and thereby LOST
the direct field-by-field scope-exit finalization it had been getting. That is
the shape `root-cause-over-microfix.md` describes as a design flaw at three
mechanisms; there are four.

Not collapsed here, deliberately: they are genuinely different questions (who is
described, who is walked, which codegen path, what the copy does), and the
`ClassFieldNeedsFinal` header explains why widening `FieldIsManaged` in
particular is a much broader change. But anyone touching one of them should
assume the other three disagree until measured.

### Every shape in this family had a probe that reported success

Worth keeping, because it is why the family took four passes rather than one:

- a promo/variant field as a record's ONLY member: clean, because the record is
  not managed and scope exit finalizes the field directly
- the same field, once a second managed member exists: LEAKS, because the record
  is now walked and the walk did not describe it
- a fixed array of Variant as the ONLY member: clean, same reason
- the same array with a second managed member: LEAKS, 3799
- the array as its own local, not a member: clean
- a plain local record: clean; the same record inside a dyn array: LEAKS

In every pair the obvious minimal probe is the clean one. A one-field test
program reports success for all four bugs.

### Regression tests

`test_record_variant_member_leaks`, `test_record_promo_member_leaks`,
`test_managed_record_gate_leaks`, `test_managed_member_array_leaks` — all wired
with `expect_same` + `assert_no_leak` at bound 50. Each was negative-controlled:
with its own fix reverted the leak row measures 7357 / 1904 / 4988 / 18967
respectively, so none of them is a test that cannot fail. The correctness rows
pass either way in every case, so the leak count is the load-bearing assertion —
except for the retain halves, where reverting only the retain arm destroys
survivors (3/6000) and segfaults under -dPXX_HEAP_DEBUG.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7b84f7d9a.
