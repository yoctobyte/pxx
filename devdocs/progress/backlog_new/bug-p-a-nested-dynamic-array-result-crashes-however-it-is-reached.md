---
slug: bug-p-a-nested-dynamic-array-result-crashes-however-it-is-reached
title: "A function returning `array of array of T` segfaults on the first index, even through a variable"
track: P
prio: 40
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "`m := MakeMat; WriteLn(m[1][0])` where MakeMat returns `array of array of Integer` SEGFAULTS — on the pinned compiler and on HEAD. Nothing to do with indexing the call result directly: the value is already wrong by the time it reaches a variable, so the nesting is lost somewhere between the callee's Result and the caller's slot."
---

# Measured, 2026-08-25 (pinned AND HEAD — identical)

```pascal
type TIntArr = array of Integer;
     TMat    = array of array of Integer;   { the named-alias spelling behaves the same }
function MakeMat: TMat;
var r0, r1: TIntArr;
begin
  SetLength(r0, 2); SetLength(r1, 2);
  r0[0] := 1; r0[1] := 2; r1[0] := 3; r1[1] := 4;
  SetLength(Result, 2); Result[0] := r0; Result[1] := r1;
end;
var m: TMat;
begin
  m := MakeMat;
  WriteLn(m[1][0], ' ', Length(m), ' ', Length(m[1]));   { fpc: 3 2 2 }
end.
```

pxx prints the leading literal and then **SIGSEGV**. `Length(MakeMat[1])` dies
the same way. The one-level case (`array of Integer` returned and indexed) is
correct in every spelling — see
[[compat-pascal-index-a-function-call-result]] and
`test/test_index_a_dynamic_array_call_result.pas`.

# Why it is filed separately

It was hit while landing the call-result indexing fix, and the first suspicion
was that fix. It is not: **the via-VARIABLE spelling crashes identically on the
PINNED binary**, so the defect is older and lives below the indexing question —
somewhere in how a nested dyn-array RESULT is built, returned or stored, not in
how it is subscripted.

A related smell found in passing, worth checking first: `SetLength(Result[0], 2)`
— sizing the inner array through `Result` — is refused outright with *"SetLength
expects an array variable in IR codegen"*, which is why the repro above has to
build `r0`/`r1` as locals and assign them in. Both point at `Result` of a nested
dyn-array type not carrying its full shape.

# Suspected, NOT measured

`ProcRetDynDepth` is the obvious suspect (`ArrTypeDynDepth` for the alias arm,
the hardcoded `retDynDepth := 1` for the literal `array of` arm in
`compiler/pasparser_proc.inc` ~944). But the via-variable crash means the value
itself is wrong, so check what the CALLEE writes before blaming what the caller
reads — `PXXDBG=a.symptr:*` on Result, then the IR of the return.

# Gate

`make compiler/pascal26` + the repro above matching `fpc -O1` + `tools/gate.sh
quick`. Add the two-level rows to
`test/test_index_a_dynamic_array_call_result.pas`, which deliberately omits them
today.
