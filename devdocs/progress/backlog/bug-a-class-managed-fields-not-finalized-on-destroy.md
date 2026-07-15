---
summary: "a class's managed fields (ansistring / dynarray / COM interface) are NOT released when the object is destroyed — pxx finalizes managed fields only for VALUE records, so every managed class field leaks on Free (silent)"
type: bug
track: A
prio: 40
---

# Class managed fields are not finalized on destruction

- **Type:** bug (correctness — object finalization / managed-field lifetime). **Silent** (a leak, not a crash).
- **Track:** A (IR/codegen of class destruction + the managed-record RTL path).
- **Found:** 2026-07-15 by agent-A while landing
  [[feature-com-interface-managed-lifetime]] item 3 (record fields).

## Symptom

A managed field of a **class** instance is never released when the object is
freed. The managed-field finalization machinery
(`EmitLayoutRTTI` → `PXXRecordRelease`, descriptor member kinds
String/DynArray/Record/Interface) is built and driven **only for value records**
(`EmitLayoutRTTI` gates on `UClsIsRecord[ci]`). A class is not a record, so it
gets no managed descriptor and `PXXRecordRelease` is never called on its
instance — the destructor runs (user `Destroy` + `FreeMem`) but the field's own
managed payload is orphaned.

Confirmed for a COM interface field (the referenced object's destructor never
fires on `Free`):

```pascal
program p; {$mode objfpc}{$H+}
type
  IThing = interface ['{B0000000-0000-0000-0000-000000000099}'] procedure Go; end;
  TThing = class(TInterfacedObject, IThing) destructor Destroy; override; procedure Go; end;
  THolder = class f: IThing; destructor Destroy; override; end;
destructor TThing.Destroy; begin writeln('DTOR-thing'); inherited Destroy; end;
procedure TThing.Go; begin end;
destructor THolder.Destroy; begin writeln('DTOR-holder'); inherited Destroy; end;
var h: THolder;
begin
  h := THolder.Create;
  h.f := TThing.Create;
  h.Free;   { prints only 'DTOR-holder' — the interface field leaks (no 'DTOR-thing') }
end.
```

Architecturally the same hole applies to an **ansistring** or **dynamic-array**
class field: same unhandled path (no per-class managed descriptor), so they leak
on destruction too. (The interface case is the one that is easy to *observe*, via
the referenced object's destructor; a leaked string is silent.)

## Fix direction

Give classes the same managed-field finalization value records already have:

1. Emit a managed-field descriptor for a class whose fields (own + inherited
   chain) include any managed member — extend `EmitLayoutRTTI` beyond
   `UClsIsRecord`, walking the parent chain so inherited managed fields are
   covered once.
2. In the class-destruction codegen (the `Free`/`FreeInstance` path, after the
   user destructor and before `FreeMem`), call `PXXRecordRelease(instance, desc)`
   using that descriptor. Interface fields already have descriptor member kind 4.
3. Cross backends: the release call must be emitted on every target's destroy
   path (x86-64 + the five cross backends), like the record path.

Watch-outs: inherited fields (walk `UClsParent`), the `TInterfacedObject`
refcount field itself must not be double-counted, and destruction order vs.
`inherited Destroy` (FPC finalizes fields after the whole `Destroy` chain, at
`FreeInstance`). Gate on self-host byte-identical + the interface + OOP corpus.

## Acceptance

The repro above prints `DTOR-thing` then `DTOR-holder` (field released on
`Free`); an ansistring/dynarray class field is released on destruction (a
leak-counter or valgrind-style check); self-host byte-identical; cross targets
green.
