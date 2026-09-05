---
slug: bug-a-wasm32-refuses-a-load-of-an-interface-valued-record-field
track: A
prio: 35
type: bug
status: done
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

---

## RESOLVED 2026-09-06 (frankwasm) — fixed in the IR, not in the backend

The ticket said the discriminator is `UClsIsInterface`, not the type kind, and
that whoever took it "needs the node's record id at `WasmEmitLoadMem`, which is
the part to establish first." **That turned out to be the wrong place to want
it.** The IR has no per-node record id (only `IRArgRecId` and
`IRSetLenBaseRec`, both narrow), so getting one to the backend meant adding a
table — and the moment that is the shape of the fix, the question is why each
backend is being told a fact it should never have had to know.

**The ambiguity is created at lowering, so it is fixed at lowering.** An
interface-valued field/deref read is now tagged `Ord(tyPointer)`, which is the
arm DIRECTLY ABOVE it in the same `if` chain, one type along: a dynamic-array
handle read already forces pointer width for the identical reason (*"ASTTk tags
it with the ELEMENT type ... force a full pointer-width load"*). Two things
that also already existed, a few hundred lines up:

  - `NodeIsInterface(node)` — the exact predicate, comment and all;
  - `IRIntfInstanceWord`, which lowers an interface value as
    `IR_LOAD_MEM ... Ord(tyPointer)` for identity comparison.

The primitive, the predicate and the precedent were all present. This site did
not ask. No backend now carries the distinction and none can get it wrong
separately — `normalise-dont-special-case`, and it deletes the case rather than
adding one.

**The ticket's warning was right and is worth keeping.** Widening wasm32's
non-scalar arm to `or (tk = tyRecord)` compiles, self-hosts, and silently yields
`@r.I` where `r.I` was wanted; both are i32 and the module validates.

### Width, checked rather than assumed

`{IMT, instance}` — a FAT pointer — appears in this tree describing an
interface, which would make a pointer-width load wrong. It does not apply here:

```
SizeOf(IFoo)=8  SizeOf(Pointer)=8   native
SizeOf(IFoo)=4  SizeOf(Pointer)=4   wasm32
```

Exactly one pointer on each. A thin instance pointer, matching
`IRIntfInstanceWord`'s own comment (*"an interface value BEING a single
instance pointer (FPC's ABI)"*).

### Evidence

  - repro: `native ok TRUE`, `wasm32 ok TRUE` (was refused)
  - `test/test_assign_lvalue_shapes_ok.pas` — the ticket's named guard, and the
    only wasm32-broken body outside the NilPy PAL group — now prints
    `lvok 16 a sh sh z 1 TRUE 7` on wasm32, identical to native
  - **58 of 58 NATIVE binaries byte-identical** pre/post. This is a shared-IR
    change, so the target that already worked is the one at risk, and the fix
    is a true no-op there.
  - **wasm32: 54 byte-identical, 1 differs — the repro.** That row is the
    positive control: without it the native run above proves only that nothing
    changed anywhere, which is equally consistent with a comparison that cannot
    see changes at all.
  - `check_intf.sh` REJECTS the pre-fix compiler, run rather than reasoned
  - `gate.sh quick` green but for `pinned builds live lib/rtl`, the known
    fleet-wide red awaiting a pin; log read rather than assumed — it names
    `pyvar_is_objtag`/`pyvar_is_inttag` and reports the LIVE compiler building
    all 54 root units cleanly

### The guard, and why it is NOT a cross row

The ticket asks to "wire it as a wasm32 cross row". Deliberately not done.
A Makefile cross row goes through `run_target.sh`, and frankD measured that the
row's command substitution DISCARDS its exit code, so a `RUNNER-ABSENT:` reply
is compared as TEXT and auto-files as a compiler regression;
`grep -n 'RUNNER-ABSENT' tools/testmgr.py` returns nothing, and seven put 1135
Makefile rows on that path. Wiring a new one today reproduces that by
construction.

`test/wasm/check_intf.sh` instead, in `check_all.sh`. Both sources, native as
the oracle so no expected value is written down twice.

**`<> nil` is deliberately not the assertion.** A skipped load yields the
FIELD'S ADDRESS, which is also non-nil — the obvious check passes on the exact
defect it exists to catch. The load-bearing rows CALL through the interface,
via a record pointer and directly off the field, with the adjacent Integer
field asserted intact against a wrong-width smear. The check also asserts the
refusal census is EMPTY, because a body this backend cannot lower does not fail
the compile: it becomes `unreachable` and the module still validates and still
runs, which is how this bug presented and is what the positive control tripped
on.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b80735a76.
