---
track: A
prio: 65
type: feature
blocked-by: []
summary: "TypeInfo(T) now answers kind + name for every category that has a consumer, but every non-class/record blob writes a nil DataPtr — no TTypeData. The data is all already in the compiler (subrange bounds, set element enum, array element type and dims); this is emission, not discovery. Plus the three categories with no consumer yet: interfaces (14), metaclasses (28), Currency (4, which needs a type-system change first)."
status: done
owner: frank1-A-typeinfo
---

# A TypeInfo TTypeData payloads, and the last three categories

- **Track A** (`compiler/rtti_emit.inc` `EmitTypeInfoHeaders`, `lib/rtl/typinfo.pas`).
- Tail of [[feature-typeinfo-all-types]], which is resolved: kind and name are
  right for scalars, strings, enums, classes, records, subranges, sets,
  procedural types, method pointers, `string[N]`, static and dynamic arrays,
  Pointer, Variant, and generic parameters at specialization time — every one
  diffed against an FPC 3.2.2 oracle. This is what it deliberately did NOT do.
- **Not urgent on purpose:** nothing in the corpus reads `DataPtr` for these
  kinds today. Do it when a consumer needs it, so the layout is designed
  against a real reader rather than guessed.

## 1. `DataPtr` is nil for every new category

`TTypeInfoHdr` is `{Kind:Int64; NamePtr:PString; DataPtr:Pointer}`. Classes and
records point `DataPtr` at their existing RTTI blob; everything else writes
nil. FPC puts a `TTypeData` there, and the inputs are all already in the
compiler — this is emission, not discovery:

| kind | what FPC's TTypeData carries | where pxx already has it |
| --- | --- | --- |
| subrange / ordinal | OrdType, MinValue, MaxValue | `AliasSubLo` / `AliasSubHi`; `TypeKindSize`/`TypeKindSigned` for the plain scalars |
| set | element type ref | `AliasElemTk` (element enum id) |
| static array | element type, dim count, bounds | `ArrTypeElemTk` / `ArrTypeNDims` / `ArrTypeDimLo` / `ArrTypeDimSpan` |
| dyn array | element type | `ArrTypeElemTk`, `ArrTypeDynDepth` |
| procvar / method | signature | `AliasProcSig` (a `Procs[]` row) |

Design it against `lib/rtl/typinfo.pas` (`PTypeData` is currently an alias of
`PTypeInfo` — "same header for now"), and pick ONE shape rather than a
per-kind struct, the way the header itself is uniform across categories.

## 2. Interfaces (14) and metaclasses (28)

Straightforward once something asks: both already have class-side bookkeeping.

## 3. `Currency` (4)

pxx has **no `tyCurrency`** at all — this is a type-system item, not an RTTI
one, and RTTI is the least of what it needs. Do not add a TypeInfo special case
for it; the kind falls out once the type exists.

## 4. `PChar` and pointer aliases

`TypeInfo(PChar)` is still refused. FPC answers `PChar` / 29 tkPointer. Named
pointer aliases go through `RegisterPtrAlias`, so `FindTypeAlias` should reach
them — check whether the miss is the alias lookup or `PChar` being a builtin
that never enters the table, and fix the one that is actually wrong. Bare
`Pointer` and `CodePointer` already work (they resolve through
`BuiltinTypeNameTk`).

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`, and extend the four
`test_typeinfo_...` programs already in `test/` — every row in them was diffed
against FPC 3.2.2 and new ones must be too, not recalled. The one deliberate
divergence is [[decide-typeinfo-scalar-name-spelling]].

---

## Done — 2026-08-25 (Track A)

Section 1 is done. **The consumer arrived**, which is what the ticket was
waiting for: `generics.defaults.pas:2082` fails to compile with

```
error: "OrdType": a pointer has no members
```

because `lib/rtl/typinfo.pas` declared `PTypeData = PTypeInfo`
([[gap-b-typinfo-ptypedata-has-no-ordtype-and-is-just-ptypeinfo]]). So the
layout below was designed against **that** reader —
`TComparerService.SelectIntegerComparer` switching on ordinal width — and not
against a guess. Sections 2-4 still have no consumer and split out as
[[feature-typeinfo-last-categories]].

### The layout, and why this one

**ONE fixed record, ten uniform 8-byte slots** (`TYPEDATA_SIZE = 80` in
`compiler/defs.inc`; `TTypeData` in `lib/rtl/typinfo.pas`), not FPC's variant
record keyed on `TTypeKind`:

| off | field | what it means |
| --- | --- | --- |
| +0 | `OrdType: TOrdType` (+4 pad) | ordinal width; the ELEMENT's width for tkSet |
| +8 | `FloatType: TFloatType` (+4 pad) | tkFloat only |
| +16 | `MinValue: Int64` | ordinal low bound; a set's element low bound; 0 for `string[N]` |
| +24 | `MaxValue: Int64` | ordinal high bound; **N** for `string[N]` (FPC's `MaxLength`) |
| +32 | `ElemKind: Int64` | `Ord(TTypeKind)` of the element/component type, 0 = none |
| +40 | `ElemRef: Pointer` | the element type's OWN blob — `PEnumRTTI` / `PClassRTTI` |
| +48 | `ElemSize: Int64` | bytes per element |
| +56 | `ElemCount: Int64` | static array: total elements, dimensions flattened |
| +64 | `DimCount: Int64` | static array: dimensions. dyn array: nesting depth |
| +72 | `DimsPtr: Pointer` | -> `DimCount` × `{Lo,Hi}` Int64 pairs; nil for a dyn array |

Four decisions worth stating, because each had a plausible alternative:

1. **Uniform, not variant.** The ticket asked for it and the header already sets
   the precedent, but the real reason is that *we own the reader*. A variant
   record's whole job is to let a foreign layout be reinterpreted per kind; when
   the same repo emits the bytes and declares the record, that machinery buys
   nothing and costs a second code path per kind — exactly the shape
   `normalise-dont-special-case` warns about. A kind with nothing to say for a
   slot leaves it zero; **read the fields your `Kind` defines and ignore the
   rest** is the entire contract.
2. **`ElemRef` points at the element's OWN RTTI blob, not a nested
   `PTypeInfo`.** A nested header would mean the compiler emitting type info for
   types the program never named in a `TypeInfo()` call — a recursive
   registration pass, for a field whose only consumer wants to know *which enum*.
   `TPropInfo.TypeRef` already established this idiom in the same unit.
3. **`FloatType` gets its own slot** rather than overlaying `OrdType`'s. The
   first cut had one slot carrying both, since no kind is ever an ordinal AND a
   float — but the whole point of a *fixed-shape* record is that there is no
   variant part through which one slot could answer to two names, and the
   consumer spells it `td^.FloatType`. Eight bytes of static data per type buys
   the reader the name it already uses; forcing a cast would have re-introduced,
   at the reader, exactly the per-kind reinterpretation decision 1 removed.
4. **Classes and records keep their existing `DataPtr`** (`TClassRTTI` / the
   record layout descriptor). Re-pointing them at a `TTypeData` would have broken
   every reader `typinfo.pas` already has, for no gain.

`GetTypeData(ti)` is added, spelled the way FPC code spells it, so vendor
sources compile unmodified. In FPC it has to skip a variable-length inline name;
here it is one load of `DataPtr`, and it returns **nil** for a kind with no
descriptor (plain string, Variant, Pointer, procvar) — callers must check.

### Values: diffed against FPC 3.2.2, not recalled

Oracle = the same program written against FPC's own `TTypeData`
(`tools/fpc_diff_probe.sh`'s method; the probe programs are throwaway).
`test/test_typeinfo_typedata.pas` is the pxx side, wired into `test-core`.

All thirteen builtin ordinals, both floats, the subrange bounds, `string[N]`'s
length, the set's element kind/width/range, and all three array shapes' element
type, size, count, dimension count and per-dimension bounds **match FPC exactly**
— including the non-obvious ones: `Boolean` is `0..1` and not "an unsigned byte
0..255"; `Char` is `otUByte 0..255`; a plain rename `TMyInt = Integer` inherits
the BASE type's full range (FPC reports LongInt's, not a `TMyInt`-shaped
nothing); a 2-D `array[1..2,1..3]` is ONE `tkArray` with `ElemCount` 6.

**Two deliberate value divergences**, both measured and both the honest answer:

- **A subrange's `OrdType` is OUR storage width.** `TSub = 1..10` is `SizeOf` 4
  here and 1 in FPC — pxx does not narrow a subrange's storage — so we report
  `otSLong` where FPC reports `otSByte`, while `MinValue`/`MaxValue` still carry
  the declared `1..10` and match FPC exactly. This is not a compromise: the
  consumer that motivated the ticket uses `OrdType` to decide **how many bytes to
  compare**, so handing it FPC's narrower answer would make it read one byte of a
  four-byte value. Parity would be the bug here.
- **`LongWord`'s `MaxValue` is 4294967295, where FPC prints -1.** FPC's
  `MinValue`/`MaxValue` are `LongInt`, so `LongWord`'s maximum truncates; our
  slot is `Int64` and holds it honestly. The same problem returns one size up —
  a `QWord`'s 2^64-1 does not fit a signed slot either — so for `otUQWord` the
  slots are BIT PATTERNS and the reader casts (`QWord(td^.MaxValue)`),
  documented at both ends.

### Verified against the real consumer shape

The exact `generics.defaults` form — `ATypeData.OrdType` (auto-deref, no `^`)
in a `case` over `otSByte..otUQWord`, reached through
`GetTypeData(TypeInfo(T))` — compiles and selects correctly for all eight
widths plus a subrange. That is the gap unblocked, measured rather than
inferred.

### A pin is required, and it is load-bearing twice over

`lib/rtl/typinfo.pas` still *compiles* against the pinned binary, so nothing
breaks by omission — but every `DataPtr` it reads is nil until a compiler with
this change emits them, so Track B / the corpus sees payloads only after a pin.

And the pinned binary makes that worse than "no data": measured on the same
source, the pinned compiler answers `d = nil` **FALSE** for a `PTypeData`
assigned from a nil `DataPtr`, while the compiler at this sha answers TRUE. A
`GetTypeData` caller doing the correct nil check therefore segfaults when built
with the pin and behaves when built at HEAD. Some fix in the 37 commits between
the pin and this branch already covers it; noted here because it means the pin
is not optional for any consumer of this API.

### One thing this adds pressure to — [[bug-a-the-fpjson-suite-overflows-the-fixed-4096-entry-data-ptr-fixup-table]]

Every payload costs data->data relocations that were not there before: one for
the header's `DataPtr`, plus one for `ElemRef` and one for `DimsPtr` where the
kind has them. So a `TypeInfo()`d type now costs **1-3 `AddDataPtrFix` entries
instead of 0**, bounded above by `MAX_TYPEINFO_REQ` (512) types.

`MAX_DATAPTRFIX` is a fixed 4096 and is **already known to overflow** on the
fpjson rung at prio 82. This change does not cause that overflow and cannot make
an already-failing compile fail differently — but it does move every program
some tens of entries closer to the ceiling, so it is called out here rather than
left for whoever bisects the next one. The right fix is that ticket's (a fixed
table is the defect; growing the constant only moves it), and this is one more
reason the table should become dynamic rather than larger.

### Not touched, filed instead

`PxxTkToFPCKind` reports `tkInteger` (1) for `tyNativeInt` / `tyNativeUInt`;
FPC 3.2.2 on x86-64 answers `tkInt64` (19) / `tkQWord` (20), because `NativeInt`
IS `Int64` there. Our payload is self-consistent (`OrdType` is `otSQWord`, the
range is 64-bit) so nothing reads a wrong value today, but the KIND is a
target-dependent answer we give unconditionally. That is a pre-existing
kind-mapping defect, not a payload one — it goes to
[[feature-typeinfo-last-categories]] rather than widening this change.

### Gate

`make compiler/pascal26` (converged, byte-identical self-host fixedpoint) +
`test/test_typeinfo_typedata.pas` + the consumer-shaped repro +
`tools/gate.sh quick`.

## Log
- 2026-08-25 — resolved, commit 1a7b554fa.
