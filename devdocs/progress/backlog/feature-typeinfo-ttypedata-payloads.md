---
track: A
prio: 65
type: feature
blocked-by: []
summary: "TypeInfo(T) now answers kind + name for every category that has a consumer, but every non-class/record blob writes a nil DataPtr — no TTypeData. The data is all already in the compiler (subrange bounds, set element enum, array element type and dims); this is emission, not discovery. Plus the three categories with no consumer yet: interfaces (14), metaclasses (28), Currency (4, which needs a type-system change first)."
status: backlog
owner: unassigned
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
