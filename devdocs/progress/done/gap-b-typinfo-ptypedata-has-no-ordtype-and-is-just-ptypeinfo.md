---
slug: gap-b-typinfo-ptypedata-has-no-ordtype-and-is-just-ptypeinfo
title: "`lib/rtl/typinfo.pas` aliases PTypeData to PTypeInfo, so `ATypeData.OrdType` has no field to find"
track: B
prio: 78
type: gap
blocked-by: [feature-typeinfo-ttypedata-payloads]
status: done
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

---

## Done — 2026-08-25, by Track A

Nothing is left for Track B here. This gap arriving is what unparked
[[feature-typeinfo-ttypedata-payloads]] (which had been held at prio 25 with an
explicit "do it when a consumer needs it, so the layout is designed against a
real reader"), and the reader it was then designed against is the
`SelectIntegerComparer` snippet at the top of this ticket.

`lib/rtl/typinfo.pas` now declares `TOrdType`, `TFloatType`, a real
`TTypeData` record with `PTypeData = ^TTypeData`, and `GetTypeData` spelled the
way FPC code spells it. The compiler emits the payload
(`compiler/rtti_emit.inc` `EmitTypeData`), so the fields carry values rather
than existing as declarations: every one was diffed against an FPC 3.2.2 oracle.

Verified with the exact shape this ticket reported — `ATypeData.OrdType`
auto-deref in a `case` over `otSByte..otUQWord`, reached through
`GetTypeData(TypeInfo(T))` — for all eight ordinal widths and a subrange, plus
the `ATypeData.FloatType` arm over `ftSingle`/`ftDouble`.

Two things the scope note above asked about, answered explicitly:

- **`FloatType` is a real field, not a cast.** It has its own slot; the first
  cut had it sharing `OrdType`'s and that was changed precisely because this
  ticket names it as something calling code spells by name.
- **The class fields (`ClassType`, `ParentInfo`, `PropCount`, `UnitName`) are
  deliberately NOT on `TTypeData`.** A class's `DataPtr` already points at the
  `TClassRTTI` blob `typinfo.pas` has always read, which carries `ParentRTTI`,
  `PropCount` and the rest; re-pointing it would break every existing reader for
  no gain. If a vendor source insists on the `GetTypeData(ti)^.ClassType`
  spelling, that is a separate, additive item — file it when one does.

**A pin is required** before anything outside this branch sees the payloads: the
pinned binary emits a nil `DataPtr`, and (measured, same source) it also answers
`d = nil` FALSE for a `PTypeData` assigned from one — so a correct nil check
segfaults when built against the pin and behaves when built at HEAD.

Landed with [[feature-typeinfo-ttypedata-payloads]]; the categories that still
have no consumer moved to [[feature-typeinfo-last-categories]].

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
