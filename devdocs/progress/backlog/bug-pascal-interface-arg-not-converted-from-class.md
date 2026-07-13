---
prio: 50
---

# passing a CLASS instance to an INTERFACE parameter stores a raw object pointer — later interface calls jump into data

- **Track:** P (Pascal frontend / interface coercion)
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

## Where
IRLowerCallArg (interface param + tyClass arg → build the same fat pointer the
assignment path builds, via IRMaterializeIntfCast). Also check the ctor-call
argument path (bespoke push loop in ir_codegen) and method calls.

## Why it matters
fpcunit's real console/XML runners attach listeners this way; any COM/CORBA
callback registration does. Currently silent memory corruption.

## Gate
`make test` + self-host byte-identical; a b-test with a unit-declared interface
+ program-declared implementor, registered through a call argument.
