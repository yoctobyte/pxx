---
prio: 58
---

# TObject RTTI reflection: MethodAddress / MethodName / GetMethodList (+ instance->RTTI link)

- **Type:** feature (Track A — RTTI/runtime)
- **Track:** A — core (rtti_emit.inc, parser builtins, VMT layout)
- **Status:** backlog — opened 2026-07-12.
- **Owner:** —
- **Blocks:** [[feature-pascal-corpus-fpcunit]] (test discovery is RTTI-driven), and
  it is the same machinery [[project RTTI→streaming→LFM]] wants.

## Why
fpcunit discovers its tests by **enumerating published methods by name** at
runtime (`TTestCase` finds every `Test*` method via RTTI, then calls it). That is
the one surface the self-host gate never exercises, and it is the reason fpcunit
was picked as rung 1 of the OOP corpus ladder. Nothing else in the ladder can run
until it exists — every FPC library's suite is written against fpcunit.

## What already exists (verified 2026-07-12, do not re-derive)
The RTTI blob **already carries a published-method table**. `EmitRTTI`
(rtti_emit.inc) writes, per class with >=1 published member:

| offset | field |
| ---: | --- |
| +0  | name (char*) |
| +8  | parent RTTI ptr |
| +16 | instance size |
| +24 | VMT ptr |
| +32 | propCount |
| +40 | props ptr |
| +48 | **methCount** |
| +56 | **meths ptr** |
| +64 | fieldCount |
| +72 | fields ptr |

`RTTI_CLS_SIZE = 80`; a method entry is `RTTI_METH_SIZE = 16` = `{name ptr, code
ptr}` (code patched via MethodFixups, like the VMT). So the *data* is there and
already links names to callable addresses — only the runtime API is missing.

Also already true: a **`TClass` / metaclass value IS the RTTI blob pointer**
(`AN_CLASSREF` yields PClassRTTI), so a `GetMethodList(AClass: TClass; ...)` can
read the blob directly with no new plumbing.

## The one missing primitive: instance -> RTTI
`[instance+0]` is the VMT address (the per-class runtime identity used by is/as).
The RTTI blob points AT the VMT (+24), but there is no back-pointer, so an
*instance* cannot find its own RTTI.

Emit the RTTI pointer in a header word **immediately before** the VMT and keep
`UClsVMTOffset` pointing at the first virtual slot (parser.inc ~15537, where the
VMT is reserved). Then `RTTI = [[instance+0] - 8]`, every existing virtual slot
index is unchanged, and `is`/`as` keep comparing VMT addresses exactly as today.
Patch it in EmitRTTI with `AddDataPtrFix(UClsVMTOffset[ci] - 8, UClsRTTIOff[ci])`.

## Scope
1. instance->RTTI backlink (above).
2. `TObject.MethodAddress(const name): Pointer` — walk own + ancestor method
   tables, case-insensitive name compare.
3. `TObject.MethodName(addr): string` — the reverse.
4. `GetMethodList(AClass: TClass; AList: TStrings)` — testutils' helper.
5. Calling a discovered method: fpcunit invokes it through a `TTestMethod` method
   pointer ({code, self}); pxx already has method-pointer records.

`TObject.GetInterface(IID, out obj)` (runtime interface lookup by GUID) is a
SEPARATE ticket — testutils only needs it for `QueryInterface`, and pxx interfaces
default to CORBA (no GUID table). Do not conflate.

## Gate
`make test` + self-host byte-identical (VMT layout changes — this MUST be
byte-identical or the layout change is wrong) + cross.

## Log
- 2026-07-12 — opened. Split out of [[feature-pascal-corpus-fpcunit]] once the
  parse-level walls there were cleared and the RTTI layout was mapped.
