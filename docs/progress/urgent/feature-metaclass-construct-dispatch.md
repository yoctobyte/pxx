# feature: metaclass-dispatched construction — `classRef.Create` (virtual ctor via a `class of`)

- **Type:** feature (Track A — codegen / VMT dispatch)
- **Status:** urgent
- **Found:** 2026-06-23, making the .lfm streaming loader run constructors
- **Severity:** high — the keystone for streaming components, FPC/LCL source
  compatibility, and any class-factory pattern.

## The precise gap (probed 2026-06-23)

`class of` metaclasses and virtual constructors already PARSE, type-check and
work for direct construction. What is broken is **constructing through a
metaclass variable**:

```pascal
type
  TBase = class tag: Integer; constructor Create; virtual; end;
  TDer  = class(TBase) constructor Create; override; end;
  TBaseClass = class of TBase;
constructor TBase.Create; begin tag := 1; end;
constructor TDer.Create;  begin inherited Create; tag := 2; end;
var c: TBaseClass; o: TBase;
begin
  o := TDer.Create;   { direct: WORKS  -> tag=2 }
  c := TDer;
  o := c.Create;      { via metaclass: BROKEN -> tag=4223806 (garbage) }
end.
```

`c.Create` must: dispatch through the class-ref's VMT to allocate (`NewInstance`
for the *dynamic* class `c` points at) and run its virtual constructor, then
return the new instance. Today it returns garbage (no/wrong allocation or the
ctor never runs).

## Why this is the keystone

- **Streaming:** `TReader` does the moral equivalent of
  `classRef := <metaclass for typeName>; obj := classRef.Create`. With this
  working, the streamer constructs properly and the four PCL constructor-skip
  stopgaps (`done/bug-lfm-streaming-skips-constructors`) revert to idiomatic
  constructors.
- **FPC/LCL source compatibility:** LCL code itself uses
  `GetClass(name).Create(Owner)`, `RegisterClass`, `class of TControl` factories —
  all gated on this. (North-star: someday compile parts of the LCL; near-term it
  lets our own CL be FPC-shaped.)

## Scope

1. `metaclassVar.Create` (and any virtual class method) dispatches through the
   value's VMT for the **dynamic** class, not the static base.
2. Allocation goes through the class-ref (`NewInstance`/`InstanceSize` of the
   dynamic class), zeroed, VMT stamped — then the virtual constructor body runs.
3. Bridge `GetClass(name)` (the streamer's `PClassRTTI`) to a usable metaclass
   value, OR teach the streamer to obtain a real class-ref, so streaming can call
   `.Create` on it.
4. Pass a constructor parameter through (`Create(AOwner)`) — see the companion
   Track B ticket; the dispatch must NOT assume parameterless.

## Acceptance

The repro prints `tag=2` for both the direct and the metaclass path. A streamed
form constructs its widgets via their real constructors (Canvas/arrays present),
then properties stream on top. Self-host fixedpoint holds.

## Related / not this

- `backlog/feature-metaclass-descendant-enforcement` — type-check strictness for
  metaclass assignment; orthogonal.
- `backlog/feature-object-reference-type` — the rootless `object` ref type;
  adjacent, reuses the same VMT plumbing.
- Companion Track B: `backlog/feature-pcl-component-ctor-owner` — PCL adopts the
  `Create(AOwner)` virtual-ctor shape so streamed/idiomatic construction lines up
  with FPC.

## Rejected alternative

A parameterless `TClassRTTI.CtorPtr` + manual call-by-pointer would unblock the
streamer with less work, but it is a dead end: it can't make LCL source compile,
hard-codes "parameterless" (FPC uses `Create(AOwner)`), and would be thrown away
once real metaclass construction lands. Eliah is NOT blocked (the stopgaps work),
so there is no reason to ship the shortcut — wait for this.

## Background

`docs/developer/lfm-streaming-and-constructors.md`.
