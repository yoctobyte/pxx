---
summary: "pxx accepts (and miscompiles to a crash) class-FIELD access through an interface-typed variable; FPC rejects it"
type: bug
prio: 45
---

# Field access through an interface variable is accepted and crashes (FPC rejects it)

- **Type:** bug (Track A/P — interface member resolution). pxx accepts an invalid
  construct and miscompiles it to a SIGSEGV; FPC gives a compile error.
- **Status:** done
- **Found:** 2026-07-18, while delta-debugging the pasmith interface crash
  ([[bug-pascal-interface-finalization-crash]]) — a *separate* cleaner bug (the pasmith
  program does not use this construct).

## Repro

```pascal
type
  IPas0 = interface ['{11111111-0000-0000-0000-000000000001}'] function Ic0(a: longint): longint; end;
  TIfc = class(TInterfacedObject, IPas0) fi: longint; function Ic0(a: longint): longint; end;
var iw0: IPas0;
function TIfc.Ic0(a: longint): longint; begin Ic0 := a + fi; end;
begin
  iw0 := TIfc.Create;
  iw0.fi := 100;          { field access THROUGH an interface var }
  writeln(iw0.Ic0(0));
  iw0 := nil;
end.
```

- **FPC:** `Error: identifier idents no member "fi"` — an interface exposes only its
  declared methods, never the implementing class's fields. Correct.
- **pxx:** compiles, then **SIGSEGV** at runtime.

## Why

An interface value is a single pointer to the instance, but member resolution on an
interface-typed expression must be restricted to the interface's method set. pxx instead
resolves `iw0.fi` as if `iw0` were the class, emitting a field load/store at the class
field offset through the interface pointer — which is not a valid class-instance base in
the general case (and even when it happens to alias the instance, the write corrupts
adjacent state), so a later dispatch/finalize faults.

## Fix

Interface-typed member access must accept only the interface's (and ancestors'/IUnknown's)
**methods**; a field/`property`-backing-field name is a compile error ("interface has no
member X"), matching FPC. Reject at resolution time; never lower it to a class-field
access.

## Acceptance

- The repro is rejected at compile time with a clear diagnostic (no SIGSEGV).
- A `{%FAIL}` conformance case (interface var . field).
- Gate: `make test` + self-host byte-identical.

## Note

Distinct from [[bug-pascal-interface-finalization-crash]] (which does NOT do field-access
-through-interface — that one's trigger is still in the delta-debugged middle block).
This one is minimal and FPC-oracle'd.

## Log
- 2026-07-18 — resolved, commit HEAD.
