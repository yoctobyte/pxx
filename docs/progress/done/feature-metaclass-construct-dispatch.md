# feature: metaclass-dispatched construction — `classRef.Create` (virtual ctor via a `class of`)

- **Type:** feature (Track A — codegen / VMT dispatch)
- **Status:** DONE 2026-06-23 (commit 404abe4, pinned v44 5aedd94)

## Resolution (2026-06-23)

`classRefVar.Create(args)` now allocates the DYNAMIC class the class-ref
points at and runs its virtual constructor. The repro prints `tag=2` for both
the direct and metaclass paths; parametrised + polymorphic dispatch verified
(`50/70/3`), and the GetClass(name)->metaclass->`.Create` bridge works
(`TBaseClass(GetClass('TDer')).Create(7)` = 70).

Built entirely from target-independent IR (the is/as idiom), so all backends
share one path — verified on x86-64/i386/aarch64/arm32 (identical output);
ESP rides the same shared ops. Self-host byte-identical.

Recipe (AN_METACLASS_NEW, lowered in ir.inc):
```
size := [cref+16]        { RTTI instance size }
inst := GetMem(size)     { plain alloc, no VMT stamp }
[inst+0] := [cref+24]    { stamp the dynamic class's VMT }
virtual-call ctor, Self=inst, slot = Create's VMT slot
result := inst
```
Once `[inst+0]` holds the dynamic VMT, the ctor is an ordinary IR_VIRTUAL_CALL.

Scope items 1, 2, 4 (dispatch / dynamic alloc / param passing) and the item-3
bridge are all delivered at the COMPILER level. Streamer ADOPTION (replacing the
four PCL constructor-skip stopgaps with idiomatic virtual ctors) is the companion
**Track B** ticket `backlog/feature-pcl-component-ctor-owner`.

Landmines hit: (a) the field-name token must be consumed (`Next`) before parsing
ctor args — the selector loop's entry `Next` only eats the `.`; (b) the
side-effecting virtual ctor call's result is discarded, so it must be flagged a
statement root (`IRMarkStatementNode`) or it is pruned and the ctor never runs.

New regression test: `test/test_metaclass_construct.pas` (in `make test`).

Tests: `make test` green (fixedpoint + threadsafe byte-identical, asm-emit ×5).

---

(original ticket below)

- **Status (orig):** urgent
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
