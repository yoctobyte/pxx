---
prio: 50
---

# passing a CLASS instance to an INTERFACE parameter stores a raw object pointer — later interface calls jump into data

- **Track:** A/P (interface VALUE MODEL — COM single-pointer ABI)
- **Found:** 2026-07-13 while building an ITestListener tracer for the fcl-json
  suite run (rung 2). Sidestepped there; unfixed.

## Repro shape (fcl-fpcunit, unmodified)
```pascal
type TTracer = class(TInterfacedObject, ITestListener) ... end;
var L: TTracer;
L := TTracer.Create;
Res.AddListener(L);        { AddListener(AListener: ITestListener) }
Res.  ... run ...          { TTestResult.StartTest iterates FListeners and
                             calls ITestListener methods }
```
Crashes at `call *0x20(%rax)` with rax pointing into RODATA — the "interface"
retrieved from the listener list is not a fat pointer / dispatchable value.
Passing `TTracer.Create` directly as the argument does not even parse
("near: AddListener TTracer Create").

## What works vs what doesn't
- The class→interface coercion exists for ASSIGNMENT (`intf := obj`, the CORBA
  fat-pointer build in ir.inc's AN_ASSIGN path) and for `as`.
- A class value passed as a CALL ARGUMENT to an interface-typed parameter is
  apparently NOT coerced — the raw instance pointer lands where a fat pointer
  (or COM-style interface value) is expected. FListeners then stores it, and
  the dispatch loop reads a method table from the wrong word.

## ANALYZED 2026-07-13 (fable-nightA) — root cause is the VALUE MODEL, not arg coercion
Class→interface ARG coercion works (minimal repros pass, plain and COM/GUID,
incl. storing through a param into a field and dispatching later). What fpcunit
actually does is:

```pascal
FListeners.Add(pointer(AListener));            { TFPList of raw pointers }
...
ITestListener(FListeners[i]).StartTest(ATest); { cast back, then call }
```

`Pointer(intf)` → `ITestListener(ptr)` is an idiomatic FPC ROUNDTRIP: an FPC
COM interface value IS one pointer (methods dispatch through [ptr] with
compiler thunks adjusting Self). Our interface value is a 16-byte CORBA fat
pointer {IMT, instance} — `pointer(intf)` can only keep one word, and the
rebuilt "interface" dispatches through garbage (observed: `call *0x20(%rax)`
with rax in rodata).

So the fix is a MODEL decision: real single-pointer COM interfaces (embedded
per-interface vtables in the instance + Self-adjusting thunks), or an interning
table mapping the fat pair to a stable handle so Pointer() roundtrips. The
former is FPC's ABI and what Delphi-shaped code keeps assuming; the latter is a
shim with lifetime questions. Track A ticket-sized either way.

## Why it matters
fpcunit's real console/XML runners attach listeners this way; any COM/CORBA
callback registration does. Currently silent memory corruption.

## Gate
`make test` + self-host byte-identical; a b-test with a unit-declared interface
+ program-declared implementor, registered through a call argument.
