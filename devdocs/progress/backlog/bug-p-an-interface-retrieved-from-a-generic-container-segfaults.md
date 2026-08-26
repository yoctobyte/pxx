---
track: P
prio: 52
type: bug
blocked-by: []
summary: "`f := l[0]` where l is a `specialize TFPGList<IFoo>` segfaults — Add succeeds and Count is right, so the store works and reading an INTERFACE element back out does not. Blocks the last fgl driver, ifclist.pas."
status: backlog
owner: —
---

# An interface retrieved from a generic container segfaults

Found 2026-08-26, immediately behind
[[bug-p-a-cast-as-lvalue-does-not-accept-a-builtin-type-name]]. It is NOT that
bug: `Pointer(Dest^) := Pointer(Src^)` and `T(Dest^)._Release` both compile and
run correctly now, and `test/fgl/ifclist.pas` gets past the compile it used to
fail. It then crashes at runtime, which nobody could see before because it never
built.

## Measured (pxx at `556a3b23f`; oracle `test/fgl/ifclist.expected`, which is
fpc 3.2.2's own output on the same driver and the same fgl.pp)

```pascal
program ifc5;
{$mode objfpc}
uses fgl;
type
  IFoo = interface ['{11111111-2222-3333-4444-555555555555}']
    function V: Integer;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    n: Integer;
    constructor Create(an: Integer);
    function V: Integer;
  end;
  TPlainList = specialize TFPGList<IFoo>;
constructor TFoo.Create(an: Integer); begin inherited Create; n := an; end;
function TFoo.V: Integer; begin Result := n; end;
var l: TPlainList; f: IFoo;
begin
  l := TPlainList.Create;
  l.Add(TFoo.Create(3));
  WriteLn('count ', l.Count);   { 1 -- correct }
  f := l[0];                    { SEGFAULT }
  WriteLn('v=', f.V);
end.
```

`count 1` prints, so `Add` stored the element and the list's bookkeeping is
right. The crash is on the way BACK OUT.

Two facts that narrow it:

- **The plain `TFPGList<IFoo>` is enough.** The refcounting
  `TFPGInterfacedObjectList` is not required to reproduce, so this is not about
  `CopyItem`/`Deref`/`_AddRef` — the container that overrides none of them
  crashes too. (`TFPGInterfacedObjectList<IFoo>` crashes EARLIER, inside `Add`;
  same family, more moving parts.)
- **The `CopyItem` body is fine in isolation.** Written out by hand against real
  `IFoo` variables --

  ```pascal
  if Assigned(Pointer(Dest^)) then IFoo(Dest^)._Release;
  Pointer(Dest^) := Pointer(Src^);
  if Assigned(Pointer(Dest^)) then IFoo(Dest^)._AddRef;
  ```

  -- pxx matches fpc line for line, including `Assigned` on both sides of the
  store and the `_Release`/`_AddRef` dispatch. So the interface primitives work;
  it is their use through the GENERIC that does not.

That pair points at the specialization of an interface-typed `T` — the element
kind an `array of T` gets for `T = IFoo`, and what `Get(Index): T` returns for
it — rather than at anything interface-specific in fgl's own source.

## Reach

`TFPGList<ISomething>` is the ordinary way Object Pascal keeps a list of
refcounted interfaces, so this is not an fgl quirk any more than the string
containers were. Every non-interface instantiation of the same containers passes
(`fpslist`, `list_int`, `list_str`, `map_int`, `map_str`, `objectlist` — six of
seven drivers), which is what makes this a narrow and findable defect rather
than a broken container library.

## Repro / gate

`test/fgl/ifclist.pas`, skip-listed against THIS ticket in `test/fgl/pxx.skip`.
Remove the line when fixed; `tools/run_fgl_corpus.sh` then enforces the pass
against the FPC 3.2.2 oracle and the rung goes 6/7 -> 7/7.

Gate = `make compiler/pascal26` (self-host fixedpoint) + the ifc5 repro above
printing `count 1` then `v=3` + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]] ·
behind [[bug-p-a-cast-as-lvalue-does-not-accept-a-builtin-type-name]]
