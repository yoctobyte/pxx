---
track: P
prio: 60
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "Storing @F into a procedural type whose calling convention differs from F (a cdecl type and a Pascal-convention routine, or the reverse) compiled, and the indirect call marshalled one convention into a prologue expecting the other: `type TF = function(x: Double): Double; cdecl; f := @Twice; f(21.0)` printed 0.0 on x86-64 and Nan on i386. FPC 3.2.2 refuses it (Incompatible types). Now refused too, at assignment (variable, field, element) and at argument passing, both directions."
owner: ""
---

# A routine assigned to a procedural type of another calling convention is accepted

```pascal
type TF = function(x: Double): Double; cdecl;
function Twice(x: Double): Double; begin Twice := x * 2; end;
var f: TF;
begin f := @Twice; WriteLn(f(21.0):0:1); end.   { 0.0 on x86-64, Nan on i386 }
```

FPC 3.2.2 rejects it: `Incompatible types: got "<address of
function(Double):Double;Register>" expected "<procedure variable type of
function(Double):Double;CDecl>"`.

## Fix

`ProcAddrConventionMismatch` in `ir.inc` compares `ProcCdecl` of the
destination's procedural signature with `CProcUsesCAbi` of the routine. It is
asked at both sinks:

- AN_ASSIGN, through `NodeProcSlotSig`, which covers a variable, a field and
  an element;
- the call-argument sink, through `ProcParamProcSig`.

It is the same pair of sites as the call-result check next to it. External
routines are exempt, because their convention is the library's. C and Nil
Python programs are exempt, like the sibling checks.

## Not covered: a wider gap

An arity or parameter-type mismatch (`f := @Two` where Two takes two Doubles)
still compiles in default mode, and FPC refuses it too. That is a general
procedural signature check. It is not done here, because it would reach further
into existing programs, and it needs its own measurement.

## Test

- `test/test_procvar_calling_convention_mismatch_fail.pas`: four mismatches,
  counted, so recovery is asserted too. FPC also reports four.
- `test/test_procvar_calling_convention_match.pas`: the accepted half. Its
  output equals FPC's.

Rows in `test-core` (x86-64) and `test-i386`.
