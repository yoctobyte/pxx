# bug: metaclass construction via GetClass stamps a non-canonical VMT

- **Type:** bug
- **Status:** DONE 2026-06-24 (commit 989a5c5, pinned v45)
- **Track:** A
- **Opened:** 2026-06-23

## Resolution (2026-06-24)

Root cause was NOT a wrong VMT offset — it was a **missed parse route**. The
inline cast form `TFooClass(expr).Create(args)` (the streamer's
`TComponentClass(GetClass(name)).Create(owner)`) has an `AN_PTR_CAST` base, but
`AN_METACLASS_NEW` detection only matched an `AN_IDENT` (a `class of` *variable*).
So the cast form fell through to the field-selector path → no real construction →
garbage / non-canonical `[inst+0]`. The variable form was correct all along but
had only ever been checked with `tag=` (ctor ran), never VMT identity.

Fix: detection now also fires for a metaclass-alias `AN_PTR_CAST`
(`AliasElemTk = tyClass`); construction factored into `BuildMetaclassNew` shared
by the var path (ParseLValueAST) and the cast path (ParseFactor). Both stamp the
canonical class VMT (`[cref+24]` = `cls^.VMTPtr`) — virtual dispatch + RTTI
identity hold.

Verified: `TBaseClass(GetClass('TBase')).Create(3)` → VMT == `clsB^.VMTPtr`;
`TBaseClass(GetClass('TDer')).Create(4)` dispatches `TDer.Kind` ('der'), VMT ==
`clsD^.VMTPtr`. Regression test `test/test_metaclass_getclass.pas`. Self-host
byte-identical; `make test` green. Track B can drop the four constructor-skip
stopgaps and stream via `TComponentClass(childCls).Create(parent)`.

---
- **Blocks:** feature-pcl-component-ctor-owner (streamer adoption), feature-eliah-from-lfm

## Summary

`TComponentClass(GetClass(name)).Create(args)` — the metaclass-construction
bridge that `done/feature-metaclass-construct-dispatch` advertised for the
streamer — allocates an object whose stamped VMT is **not** the canonical class
VMT. The virtual constructor dispatches and runs (so simple `tag=` tests pass),
but the resulting instance fails VMT-identity: `GetInstanceClassName` returns
`''`, and RTTI/virtual paths that rely on identity break. Streaming a component
tree this way crashes.

## Repro (lib/pcl available)

```pascal
uses gtk3, controls, stdctrls, forms, classes_lite, typinfo;
var cls: PClassRTTI; c1: Pointer; c2: TComponent;
begin
  Application := TApplication.Create; Application.Initialize;
  cls := GetClass('TButton');
  c1 := CreateInstance(cls);
  writeln(GetInstanceClassName(c1));          { 'TButton'  — correct }
  c2 := TComponentClass(cls).Create(nil);
  writeln(GetInstanceClassName(Pointer(c2))); { ''         — WRONG, expect 'TButton' }
end.
```

`CreateInstance` (the old RTTI alloc) produces an instance whose VMT matches the
registry; the metaclass path does not. Both produce a usable object for *direct*
virtual calls (e.g. CreateHandle runs), so `[cref+24]` is a functional dispatch
table — but it is a different pointer than `RTTIPtr^.VMTPtr`, the value
`GetInstanceClassName` compares against.

## Why this blocks Track B

`done/feature-metaclass-construct-dispatch` was verified only with `tag=`
assertions (ctor ran); it never checked `GetInstanceClassName` / `is` / `as` /
RTTI identity on the constructed object. The streamer (`classes_lite.TReader`)
and `is`/`as`/RegisterClass-style code need the canonical VMT. With this open,
the PCL streamer cannot adopt virtual constructors and must keep the four
`done/bug-lfm-streaming-skips-constructors` stopgaps (CreateInstance + Canvas /
array guards).

## Likely cause

`AN_METACLASS_NEW` stamps `[inst+0] := [cref+24]`. When `cref` is a `GetClass`
result (`PClassRTTI` from typinfo) rather than a compile-time class literal, the
offset that holds "the VMT" for stamping differs from the offset/pointer the
RTTI registry exposes as `VMTPtr`. Either the metaclass-new must stamp the same
VMT pointer the registry records, or `PClassRTTI` and the class-literal class-ref
must agree on the VMT field.

## Acceptance

The repro prints `TButton` for both paths. A streamed PCL form constructs its
widgets via their real `Create(AOwner)` (Canvas/arrays present, correct VMT),
and `test_pcl_lfm` / `test_pcl_event_rtti` pass with the streamer calling
`TComponentClass(childCls).Create(parent)` and the four constructor-skip stopgaps
removed.

## Log
- 2026-06-23 — filed from Track B (TComponent virtual-ctor migration). The
  Create(AOwner) shape landed; streamer adoption parked on this. Grep marker:
  `bug-metaclass-new-getclass-vmt`.
