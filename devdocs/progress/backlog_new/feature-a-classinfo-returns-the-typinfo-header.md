---
slug: feature-a-classinfo-returns-the-typinfo-header
title: "TObject.ClassInfo returns the typinfo-facade PTypeInfo, not our raw class blob"
track: A
prio: 45
type: feature
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Re-filed from decide-classinfo-returns-our-blob-or-nothing / decide-tobject-classinfo-blob-or-refusal, both decided 2026-08-25. x.ClassInfo returns exactly what TypeInfo(TThatClass) returns -- the 24-byte {Kind; NamePtr; DataPtr} header whose DataPtr points at the class blob -- so o.ClassInfo = TypeInfo(TFoo) holds and a layout walker reads a real kind byte. One header word per declared class."
---

# What to build

`x.ClassInfo` answers with the typinfo facade's `PTypeInfo` header, i.e. the
same value `TypeInfo(TThatClass)` already mints today. Returning the raw class
blob was **refused** by the decision: a walker reading
`PTypeInfo(x.ClassInfo)^.Kind` off our blob reads an interned-name pointer's low
byte as a `TTypeKind`, which is `frontend-compat-philosophy.md`'s *"silent wrong
VALUE"* — a bug in any dialect.

## Shape

- Mint a `TYPEINFO_REQ_CAT_CLASS` header **per declared class**, not per
  compile-time use. `ClassInfo` is a runtime member on a possibly-dynamic
  receiver, so it cannot be answered statically for an arbitrary instance —
  every class must carry one. Cost is one word in `.data` per class; `UnitName`
  just demonstrated the header grows freely (nothing strides over these headers;
  every reader names a field offset).
- Add the `ClassInfo` accessor arm (`GenMakeClassRefOp` is where the sibling
  members resolve).
- Unskip `tclassinfo1.pp`, whose assertion is precisely
  `TObject.ClassInfo = TypeInfo(TObject)`.

## Interaction — land after or with the kind-numbering fix

The header's `Kind` word is emitted through `PxxTkToFPCKind`
(`compiler/rtti_emit.inc:811`, `tkClass` = 15 at :896), so it already speaks
FPC's numbering. That is the standing policy confirmed by
[[decide-rtti-kind-numbering]]: **the facade speaks FPC's public numbering, the
compiler's internal tags stay private.** Nothing here changes that seam; it uses
it.

## Acceptance

- `o.ClassInfo = TypeInfo(TFoo)` is True for a `TFoo` instance, including
  through a variable of the parent's type.
- `PTypeInfo(o.ClassInfo)^.Kind` reads `tkClass`, and the name reads the class
  name.
- `tclassinfo1.pp` passes and leaves the skip list.
- Closes the ClassInfo rows of [[feature-pascal-builtin-tobject-class]] and
  [[feature-p-tobject-api-classparent-instancesize-tostring]].
