---
slug: bug-a-wasm32-refuses-a-load-of-an-interface-valued-record-field
track: A
prio: 35
type: bug
status: working
blocked-by: []
owner: frankwasm
created: 2026-09-04
found-by: frankA (wasm32 gap census, last codegen instance)
summary: "`ptr := o.I`, where o is a record with an interface-typed field, refuses on wasm32 as `load through a pointer of type record` -- an interface is spelled tyRecord and WasmEmitLoadMem only has an arm for a frozen string. Isolated to a 12-line repro. THE OBVIOUS FIX IS WRONG AND I TRIED IT: widening that arm to `or (tk = tyRecord)` makes a record-typed load yield its ADDRESS, which is right for a real aggregate and SILENTLY WRONG for an interface, whose field holds a pointer that must be LOADED. Measured: with the widening in, the refusal moves to `value of type record in assignment to ptr` on the same statement, i.e. the address was produced where the value was wanted. The discriminator is `UClsIsInterface`, not the type kind."
---

# wasm32 refuses a load of an interface-valued record field

The last codegen instance in the wasm32 gap census (2026-09-04): 26 gap
instances left, 19 of them the NilPy PAL's raw syscalls, and this is one of the
five remaining distinct codegen shapes.

## Repro

```pascal
type
  IFoo  = interface procedure Go; end;
  TFoo  = class(TInterfacedObject, IFoo) procedure Go; end;
  PIntf = record I: IFoo; end;
var o: PIntf; ptr: Pointer; ifv: IFoo;
begin
  ifv := TFoo.Create;  o.I := ifv;
  ptr := o.I;                      { <-- here }
end.
```

```
  x86-64   ok TRUE
  wasm32   main$0 — load through a pointer of type record
```

`WasmEmitLoadMem` (`ir_codegen_wasm32.inc:1326`) has one non-scalar arm, for a
frozen string, and refuses everything else by type name. An interface is spelled
`tyRecord` throughout the type system — `test_assign_lvalue_shapes_ok.pas` says
so in its own header comment — so it lands in the refusal.

## DO NOT WIDEN THAT ARM TO tyRecord. I tried it and it is wrong.

The neighbouring frozen-string arm says an aggregate's VALUE is its ADDRESS, and
`WasmEmitValueAs` states the same thing for sets, `IR_DYNUNIQUE` and
hidden-destination calls. Extending it to `or (tk = tyRecord)` is the obvious
next member of that family and it compiles, self-hosts, and is a silent
miscompile for exactly this case:

- **A real aggregate behind a pointer** — its value IS the address, so yielding
  the address is correct.
- **An interface field** — the field HOLDS a pointer, so the value is what the
  load reads, and yielding the field's address gives `&o.I` where `o.I` was
  wanted. Both are i32, so the module validates and runs.

Measured: with the widening applied, the refusal on this repro moves one step
along the SAME statement, to `value of type record in assignment to ptr`. The
address had been produced where the value was wanted; only the second refusal
stopped it from shipping. Reverted rather than left in.

## The shape of a correct fix

The discriminator is not the type kind, it is whether the record id is an
interface — `UClsIsInterface[recId - REC_UCLASS_BASE]`, which `ir.inc` already
uses (`IRLowerClassMatch`, `isComIntfArg`). An interface-spelled `tyRecord` load
is a POINTER load; a genuine record load is an address. Whoever takes this needs
the node's record id at `WasmEmitLoadMem`, which is the part to establish first.

Note the same question is live one level along in `WasmEmitValueAs`, whose
record-typed arms are all narrowed on the NODE KIND rather than the type for
this exact reason, and whose comment says so.

## Guard when it closes

The repro above, plus `test/test_assign_lvalue_shapes_ok.pas` — which is a
whole-file exercise of "none of these may be refused" and is currently the only
wasm32-broken body outside the NilPy PAL group. Wire it as a wasm32 cross row.
