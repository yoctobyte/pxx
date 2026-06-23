# bug: `@obj.Method` does not coerce to a `Pointer` (or `TMethod`) argument

- **Type:** bug (Track A — parser / call matching / type coercion)
- **Status:** done
- **Found:** 2026-06-23, wiring GTK event handlers in the Eliah IDE (Track B)
- **Severity:** high — every `OnClick`/`OnPaint`/`OnMouseDown` handler in the GUI
  path must be hand-assembled into a `TMethod` field-by-field; the natural
  `widget.OnClick := @H.Method` / `f(@H.Method)` idiom is rejected.

## Gap

The address of a method, `@obj.Method`, is not accepted where a `Pointer`
(or `TMethod`) parameter is expected. Overload matching sees the method-pointer
arg as an incompatible type and rejects the call.

```pascal
type
  TH = class procedure M(Sender: Pointer); end;
procedure TH.M(Sender: Pointer); begin end;
procedure TakesPtr(p: Pointer); begin if p = nil then ; end;
var h: TH;
begin
  h := TH.Create;
  TakesPtr(@h.M);     { fpc: ok   pxx: error: no overload of TakesPtr matches }
end.
```

Compiler output (pinned v38):

```
Mismatch in MatchProcCall: name = TakesPtr, nArgs = 1
  arg[0] = 5
  Candidate idx 159: paramCount = 1
    param[0] = 17
pascal26: error: no overload of TakesPtr matches these arguments ()
```

Arg kind `5` (method pointer) is not seen as assignable to param kind `17`
(pointer).

## Control (works)

Building the `TMethod` by hand and passing its `Code` field is accepted:

```pascal
type TMethod = record Code, Data: Pointer; end;
...
var pm: TMethod;
begin
  pm.Code := @h.M; pm.Data := h;
  TakesPtr(pm.Code);     { ok }
end.
```

`@h.M` assigned to a `Pointer` *field* (`pm.Code`) is fine; only the *argument
coercion* / overload-match path rejects it.

## Expected

`@obj.Method` should coerce to a `Pointer` parameter (its code address), matching
FPC. Ideally `@obj.Method` also satisfies a `TMethod`/`of object` parameter
(code+data captured), so `widget.OnClick := @H.Handler` works directly.

## Track B impact

The Eliah IDE wires every event by hand:

```pascal
pm.Code := @H.OnTreeClick; pm.Data := H;
H.Tree.OnClick := pm;
```

Idiomatic LCL/FPC is `H.Tree.OnClick := @H.OnTreeClick;`. Until this lands the
GUI code stays distorted (a shared `pm: TMethod` scratch var, two assignments per
handler). No app-logic workaround applied — the distortion is confined to the
wiring, and we are parking rather than bending further.

## Repro

`/tmp/l1_repro.pas` (above) fails; `/tmp/l1_control.pas` (inline TMethod) passes.

## Resolution (2026-06-23)

`@obj.Method` (AN_METHODREF) was typed tyRecord, so overload matching saw a
tyRecord arg vs a Pointer (tyPointer) param and rejected the call. But in a value
context AN_METHODREF already lowers to its CODE address (IR_PROCADDR, ir.inc) —
only the type tag was wrong. Changed the `@obj.Method` factor to type the node
tyPointer. Assignment to a TMethod target still captures code+data: AN_ASSIGN
keys on the AN_METHODREF NODE KIND (ir.inc:2467), not the type tag, so
`pm := @h.M` / `widget.OnClick := @h.M` are unaffected.

`TakesPtr(@h.M)` now compiles; control `pm.Code := @h.M`, method-var
`cb := @h.M; cb(nil)`, and the method-ptr test suite all still pass; self-host
byte-identical. Front-end only. Closes bug-method-ptr-no-coerce-pointer-arg.
(Passing @obj.Method to a TMethod parameter by value remains a follow-up — assign
context, the Eliah path, works.)
