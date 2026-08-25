---
slug: gap-b-typinfo-ptypedata-has-no-ordtype-and-is-just-ptypeinfo
title: "`lib/rtl/typinfo.pas` aliases PTypeData to PTypeInfo, so `ATypeData.OrdType` has no field to find"
track: B
prio: 78
type: gap
blocked-by: [feature-typeinfo-ttypedata-payloads]
status: backlog_new
owner: ""
created: 2026-08-25
summary: "PTypeData is declared as `= PTypeInfo` with a `same header for now` note, and TTypeInfo carries no OrdType / MinValue / MaxValue / FloatType. Any RTTI-driven code that switches on a type's ordinal width — Generics.Defaults' comparer selection, and the whole TypInfo idiom generally — cannot compile."
---

# Symptom

```
pascal26:2082: error: "OrdType": a pointer has no members
  (dereference it with ^, or the pointee type is unknown here)
```

from `generics.defaults.pas`:

```pascal
class function TComparerService.SelectIntegerComparer(ATypeData: PTypeData; ASize: SizeInt): Pointer;
begin
  case ATypeData.OrdType of
    otSByte: Exit(@Comparer_Int8_Instance);
    otUByte: Exit(@Comparer_UInt8_Instance);
    ...
```

Note the diagnostic is honest but misleading here: the auto-deref is fine, the
POINTEE simply has no such field.

# What is missing

`lib/rtl/typinfo.pas:148`:

```pascal
  PTypeData = PTypeInfo;   { same header for now — DataPtr carries anything extra }
```

FPC's `TTypeData` is a variant record keyed on `TTypeKind`, and the parts real
code reaches for are:

- ordinals — `OrdType: TOrdType` (`otSByte`/`otUByte`/`otSWord`/`otUWord`/
  `otSLong`/`otULong`/`otSQWord`/`otUQWord`), `MinValue`, `MaxValue`
- floats — `FloatType: TFloatType`
- classes — `ClassType`, `ParentInfo`, `PropCount`, `UnitName`
- and `TOrdType` / `TFloatType` themselves, which are also absent

This is a LIBRARY gap, not a frontend one — Track B — but it gates a Track P
corpus rung, so it is filed rather than left implicit.

# Scope note

The full FPC `TTypeData` is large and most of it is not needed. What
Generics.Defaults actually reads is `OrdType` and `FloatType`; growing those two
plus their enums, keyed off the existing type-info header, is a much smaller job
than modelling the whole variant record and is the right first rung.

# Where it was found

[[feature-pascal-corpus-generics]] — the wall after
[[bug-p-new-as-a-function-over-a-pointer-type-is-undefined]] cleared, at
`generics.defaults.pas:2082`.
