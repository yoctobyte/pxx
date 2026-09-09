---
slug: feature-a-classinfo-returns-the-typinfo-header
title: "TObject.ClassInfo returns the typinfo-facade PTypeInfo, not our raw class blob"
track: A
prio: 45
type: feature
blocked-by: []
status: done
owner: frankH
created: 2026-08-25
summary: "DONE 2026-09-09. `x.ClassInfo` answers the typinfo facade's 24-byte {Kind; NamePtr; DataPtr} header -- the same one TypeInfo(TThatClass) mints, shared through RegisterTypeInfoReq's (cat,key) dedup, so identity holds AND a layout walker reads a real kind byte. Blob grew 104 -> 112; the +104 word is back-linked after EmitTypeInfoHeaders because the header does not exist when the blob is filled. 13-row test byte-identical to fpc 3.2.2 and identical again on i386; two rows deliberately FALSE, and two controls run (returning the blob flips 9 of 13; disabling the back-link flips the other rows and segfaults the walker) because neither control alone certifies the file. `tclassinfo1.pp` unskipped and passing. FOUND ON THE WAY: `UnitName` shipped 2026-08-25 without its builtin-pull pre-scan trigger, so it was refused in any program with no uses clause -- measured by removing only that term and rebuilding, and reproduced on pin v407. It stayed green because every existing caller had a NEIGHBOUR that pulled the trigger; fixed, with its own bare test."
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

## 2026-09-09 (frankH) — DONE

Built as specified. `x.ClassInfo` answers the typinfo facade's 24-byte
`{Kind; NamePtr; DataPtr}` header — the same one `TypeInfo(TThatClass)` mints,
shared by construction rather than by coincidence.

### Shape as landed

| where | what |
| --- | --- |
| `defs.inc` | `RTTI_CLS_SIZE` 104 → 112; the header pointer is the +104 word |
| `rtti_emit.inc` | register a `TYPEINFO_REQ_CAT_CLASS` request for EVERY class with a blob, then back-link `blob+104` to `TypeInfoReqOff[]` after the headers exist |
| `builtin.pas` | `PXX_RTTI_CLASSINFO = 104`, `__pxxClassInfo` — one field read |
| `pasparser_call.inc` | the `ClassInfo` arm of `GenMakeClassRefOp` + `IsClassRefOpName` |
| `pasparser_prog.inc` | `classinfo` (and `unitname`, see below) on the builtin-pull pre-scan |

**The dedup is load-bearing, not thrifty.** `RegisterTypeInfoReq` keys on
`(cat, key)`, so a class the program also writes `TypeInfo()` for gets ONE
header — which is exactly what `o.ClassInfo = TypeInfo(TFoo)` asserts. If it
minted a second, every identity row would be False with nothing else visibly
wrong.

**Two phases because the target does not exist in phase one.** The blob is
written by `EmitRTTI`, the header by `EmitTypeInfoHeaders` right after, so the
+104 word is the one field whose target is unknown when the blob is filled.
Same shape as the VMT backlink at −8. Registration is a separate loop from the
emit loop because the emit loop walks `TypeInfoReqCount`, and growing that array
while iterating it would emit some headers and silently skip others.

### Acceptance, all four rows

- `o.ClassInfo = TypeInfo(TFoo)` is True, **including through a variable of the
  parent's type** — `o: TBase` holding a `TDer` answers `TypeInfo(TDer)`.
- `PTypeInfo(o.ClassInfo)^.Kind = tkClass` is True; the name reads the class name.
- `tclassinfo1.pp` passes and left `pxx.skip` (116 → 115 lines); verified through
  the real harness, `1 pass, 0 fail`.
- The ClassInfo rows of both TObject tickets are closed.

### Tests, and what each one can fail on

`test/test_tobject_classinfo.pas` — 13 rows, `.expected` byte-identical to
fpc 3.2.2 (`-Mobjfpc -O1`), and identical again on **i386**, which is the target
this repo's defaults never measure.

**TWO ROWS ARE FALSE AND THEY ARE WHY IT IS A GUARD.** `o.ClassInfo =
TypeInfo(TBase)` where `o` holds a `TDer` fails a declared-type answer; and
`TBase.ClassInfo = TDer.ClassInfo` fails a nil or shared one. Both controls were
run rather than reasoned about:

| control | what it models | result |
| --- | --- | --- |
| `__pxxClassInfo` returns `Rtti` | the refused "answer with our blob" | **9 of 13 rows flip** |
| back-link patch disabled | the machinery does nothing | the two FALSE rows flip, `<> nil` flips, the walker rows **segfault** |
| accessor absent | pre-change state | `class method not found (ClassInfo)`, a clean diagnostic |

Note the first two catch DIFFERENT rows: the blob control leaves both FALSE rows
FALSE, and the nothing-at-all control leaves `o.ClassInfo = TypeInfo(TBase)`
FALSE while flipping `TBase.ClassInfo = TDer.ClassInfo` to True. Neither control
alone certifies the file.

### A second, older defect found on the way — and it is the more useful half

`test/test_classref_member_needs_no_uses.pas`, wired separately, because it is a
**different population**: a program with **no uses clause**.

`UnitName` landed 2026-08-25 without its entry in the builtin-pull pre-scan, so
`program un; type TFoo = class end; begin WriteLn(TFoo.UnitName) end.` was
refused — from that day until today — with `class method not found (UnitName)`,
a diagnostic that names the MEMBER when what is absent is the UNIT. **Measured
by removing only the `unitname` term and rebuilding**, not inferred from
reading, and reproduced independently on pin v407.

It survived a year of green because `test_tobject_unitname.pas` `uses` a helper
unit and every other `UnitName` caller in the tree writes `ClassName` in the
same program: **the trigger was always pulled by a neighbour.** That is the
general shape worth carrying — a pre-scan trigger is only ever exercised by
programs that do not already have another reason to fire it, so the test that
covers a member does not cover the member's LINKAGE unless it is written bare.
The new file therefore has no uses clause, no `ClassName`, no `is`, and says so
at the top: adding any of them leaves every row green and destroys the guard.

### Cost, stated accurately

The ticket said "one word in `.data` per class". It is one word in the blob
**plus a 24-byte header per class** (the name string is already interned by the
blob, so that part is shared). Unconditional, because `ClassInfo` is a runtime
member on a possibly-dynamic receiver and nothing in the token stream predicts
which classes a program will ask about.

### The bootstrap question, asked because the record descriptor could not grow

`30ed522b3` withdrew a header resize on the record LAYOUT descriptor: the seed's
OLD emitter writes stage-1's `Data[]` while stage-1 links the NEW
`builtinheap.pas`, so a moved field is read at the wrong offset inside the stage
that produces the next compiler. **This header is exempt for a checkable
reason** — the compiler declares no class type and calls no class-blob accessor,
so no stage-1 binary ever dereferences a field the seed did not write. Checked
by grep (every `X = class` and every `.ClassName`/`.ClassInfo`/`.InstanceSize`/
`.UnitName` hit in `compiler/**` outside `builtin/` is inside a comment) and the
self-host fixedpoint is the running proof. The reason is written at
`RTTI_CLS_SIZE` so the next person to grow it re-asks rather than inherits
"safe to grow" as a property of RTTI headers in general.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
