---
track: A
prio: 25
type: bug
blocked-by: []
summary: "A by-value record argument is copied into a caller-frame temp that is released at the CALLER's scope exit, not when the call returns. FPC finalizes a value parameter in the callee, so an observable destroy (an interface field) happens later here — at program exit when the caller is the main body."
status: backlog
---

# A by-value record arg's temp outlives the call

Found while resolving
[[bug-a-a-record-copy-does-not-retain-an-interface-field]]; it is the one
remaining FPC divergence in that ticket's differential, and it is NOT
interface-specific — interfaces only make it observable, because a destructor
prints and a string refcount does not.

## Measured (FPC 3.2.2 vs pxx HEAD, same source)

```pascal
type TRec = record a: Integer; f: IFoo; end;
procedure ByValue(r: TRec); begin writeln(r.f.Name); end;
var g: TRec;
begin
  g.f := TFoo.Create('B');
  ByValue(g);
  g.f := nil;
  writeln(destroyed);      { FPC: 1     pxx: 0 (the temp still holds a ref) }
end.
```

Inside a PROCEDURE the two agree, because the caller's scope exit happens right
after the call. In the MAIN body they diverge until program exit.

## Cause

`IRLowerCallArg` (`compiler/ir.inc`, the `RecordHasManagedFields(argRecId)` arm)
copies the argument into a hidden `skLocal` temp with `IR_COPY_REC_MANAGED`,
which retains. Nothing releases it at the call's end; `EmitManagedLocalCleanup`
gets it at the caller's epilogue. FPC's convention is that the CALLEE finalizes
a value parameter.

## Fix sketch

Either release the temp immediately after the call returns (a per-call cleanup,
which is what the interface-argument path already does for a scalar interface
temp), or move the finalization into the callee to match FPC. The first is
smaller and does not change the ABI; the second is the FPC-parity answer and
would need every backend's prologue/epilogue to agree.

Not urgent: the reference is dropped, just late — a lifetime divergence, not a
leak. It becomes urgent if a program relies on destruction timing (a lock held
by an interface, an RAII-ish handle).

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, plus the program
above as a test with FPC-matched counts.
