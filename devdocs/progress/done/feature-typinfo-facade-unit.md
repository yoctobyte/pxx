---
prio: 72
blocked-by: [feature-typeinfo-all-types]
owner: frankB
---

# `typinfo` facade unit: FPC's RTTI API shapes over OUR blobs

- **Type:** feature (library — Track B)
- **Status:** done
- **Depends on:** [[feature-typeinfo-all-types]] (the blobs to read).
- **Blocks:** [[feature-pascal-corpus-generics]], the RTTI->streaming->LFM line,
  [[feature-embed-dwscript-rtti]], fpjsonrtti.

## The insight this rests on
Real code does NOT read FPC's RTTI bytes. It reaches RTTI through the `typinfo`
UNIT's record declarations and accessors — `GetTypeData`, `GetPropInfo`,
`GetEnumName`, `PropType`, `TTypeKind` — and **those declarations live inside
typinfo**. Since we supply typinfo, we choose what the records look like and how
they are filled. Therefore: **no FPC byte-layout parity, and no fork of any
consumer library.** (Layout would only leak for code doing pointer arithmetic
past the published API — rare; handle it if a corpus target actually does.)

## The work
Grow `lib/rtl/typinfo.pas` from its current enum-only surface into the API FPC
consumers actually call:
- `TTypeKind` enumeration + `PTypeInfo` / `TTypeData` / `PPropInfo` shapes,
  declared to be convenient over OUR blobs (not byte-copies of FPC's).
- `GetTypeData`, `GetPropInfo`, `GetPropList`, `PropType`, and the property
  get/set helpers the streaming code uses.
- Keep the existing `GetEnumName` / `GetEnumValue` / `GetEnumNameCount` (already
  the same pattern, proven by fpjson).

Honesty rule, as everywhere in this RTL: where a shape cannot be answered, say
so at the declaration rather than returning a plausible lie.

## Gate
`make lib-test` + the consumers that motivated it compile (start with
generics.defaults, then fpjsonrtti).

## Resolution (2026-08-28, frankB)

The API surface is complete and gated. **The ticket's second gate clause — "the
consumers that motivated it compile" — is NOT met by this and cannot be met from
Track B**; see the scope note at the end.

### What the unit gained

| | |
| --- | --- |
| introspection | `PropType` (by PPropInfo and by class), `PropIsType`, `IsPublishedProp`, `IsStoredProp`, `TTypeKinds`, kind-filtered `GetPropList` |
| typed accessors | `GetFloatProp`/`SetFloatProp`, `GetInt64Prop`/`SetInt64Prop`, `GetObjectProp`/`SetObjectProp`, `GetEnumProp`/`SetEnumProp` (by name), `GetSetProp`/`SetSetProp` (by name), `SetToString`, `StringToSet` |
| FPC field spellings | `TTypeData` grew a variant part carrying `elSize`, `MinInt64Value`, `MaxInt64Value` at the same offsets as our `ElemSize`, `MinValue`, `MaxValue` — identical storage, nothing tag-keyed, so it is not the kind-keyed variance the record deliberately avoids |

The field-spelling arm exists because of frankA's measurement of vendored
`rtl-generics`: `Generics.Defaults`'s entire typinfo requirement is five
`TTypeData` fields at nine sites, and **three of the five were unspellable
here** — a facade whose field names differ from FPC's is not a facade, since the
consumer would need editing, which is the one thing the design promised to avoid.

### Diffed against FPC 3.2.2, not assumed

- **All twelve `OrdType`/`FloatType` values are identical to FPC's**, run for
  run (ShortInt through QWord, Boolean, Char, Single, Double). This is the part
  that actually gates the consumer: frankA measured both fields as used *only*
  as case selectors dispatching to a comparer, so a wrong ordinal silently
  selects the wrong one.
- **`GetSetProp`'s default was measured, not recalled**, and it is the
  surprising one: FPC returns `clRed,clBlue` with NO brackets and
  `[clRed,clBlue]` only with `brackets=True`. The first implementation here
  always bracketed. Both forms are now asserted.

### One bug found and fixed underneath it

[[bug-b-rtti-read-of-a-getter-method-property-answers-zero]] — `GetOrdProp` and
`GetStrProp` handled only direct-field properties and answered 0 / `''` for a
read METHOD, while the write half already dispatched through setter methods.
The facade could not be built on top of that.

### One bug found and NOT fixed — it is a compiler defect

[[bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer]] (Track P,
filed). pxx lets a class instance convert implicitly to any typed pointer, which
FPC rejects outright. Two consequences: a silent memory-safety hole with no cast
written, and — the one that bites here — a pointer-taking overload becomes a
viable, *preferred* candidate for a class argument. So the instance-taking
overloads (`GetPropInfo(AnObject, 'Caption')`, the spelling every FPC consumer
uses) are **declared but never selected**: the call binds to the `PClassRTTI` arm
and segfaults.

Those overloads are LEFT IN PLACE as platonic code per the standing rule, with
the hazard stated at the declaration so their presence is not read as a promise,
and the test routes through `GetInstanceRTTI` with a note pointing at the ticket.
The hazard predates them — the same call bound to the pointer arm and crashed
before they existed.

### Deliberate omission

`FindPropInfo` (FPC's raising form of `GetPropInfo`) is absent: raising needs an
`Exception` class, which needs a `uses`, and this unit deliberately has none —
`streams`, `classes_lite`, `lfm` and all of `lib/pcl` sit on it. Named at the
declaration rather than faked. Revisit deliberately if a corpus target calls it.

### Gate

`make lib-test` green with `test/lib_typinfo_props.pas` (63 rows) wired in;
`make demos` 35/35. Both against stable v389 (`325b4479070a`).

### Scope note — this does NOT make the generics rung green

Recorded because the dependency graph invited the opposite reading. Per frankA's
compile of vendored `rtl-generics`, typinfo is **one of four walls** in
`generics.defaults.pas`; two of the others are Track P compiler defects and one
is a SysUtils ask filed separately. `generics.collections` (4,165 lines) is
blocked only *through* defaults and has never been independently assessed, so a
second round of findings should be expected. Nothing here was verified against
the vendored tree — it is not in this checkout.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
