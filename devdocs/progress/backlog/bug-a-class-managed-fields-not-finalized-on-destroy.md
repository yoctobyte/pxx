---
summary: "managed-field finalization gap + heap-lock hazard: a class finalizes NO managed fields on Free (leak), and a COM interface field of a RECORD cannot be finalized under the record heap lock without deadlocking — both need the interface release moved outside the non-reentrant heap lock"
type: bug
track: A
prio: 40
---

# Class managed fields are not finalized on destruction

## The heap-lock hazard (read first — blocks the COM interface field case)

Record-field managed finalization runs under the heap spinlock
(`EmitAcquireHeapLock` around `PXXRecordRelease`, at every record-finalize site
on all six backends). String/dynarray members are safe there because `PXXFree`
assumes the caller holds the lock and does not re-acquire. A **COM interface**
member is NOT safe: its `PXXIntfRelease -> _Release -> Free -> FreeMem` routes
through the SELF-LOCKING `FreeMem`, which re-acquires the non-reentrant spinlock
and spins forever. Confirmed: a `{$threadsafe on}` program with a record holding
a COM interface field prints the destructor then hangs. So interface-field
finalization (record OR class) requires the interface release to happen OUTSIDE
the heap lock: either (a) a **reentrant heap lock** (owner + depth — needs a
per-thread identity / TLS), or (b) a **separate unlocked interface-release pass**
emitted before the locked string/dynarray pass at every finalize site. Both are
heap-critical and must be validated by the threading stress tests, not just the
single-threaded native tier. The COM record-field attempt (cb2ed843) hit exactly
this and was reverted (87108477) to a benign leak.

Scope-exit interface LOCALS and by-value interface param temps are already
finalized correctly and threadsafe (they call `PXXIntfRelease` WITHOUT holding
the heap lock — `EmitManagedLocalCleanup` does no lock wrap). Only the
record/class FIELD path (which holds the lock) is blocked.

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
