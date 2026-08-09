{ Function results of the AGGREGATE kinds, every line diffed against FPC.

  Two silently wrong answers, both pre-existing and both found by that diff:

  * a SET-returning function answered the EMPTY set, whatever its body did, on
    every target. `FuncName := [1, 4]` leaves the LHS ASTTk unset, so the set
    arm — which tested the node type only — missed it and the scalar store path
    wrote the literal's ADDRESS into the 32-byte Result slot. The record arm
    beside it already carried the symbol-TypeKind fallback for exactly this; the
    set arm was the sibling that never got it.

  * a FIXED-ARRAY-returning function (one-dimensional; an N-D result is
    refused, see bug-a-nd-array-function-result-indexes-the-wrong-slot)
    answered element 0 and zeros
    (`8 9 10` came back as `8 0 0`). `Procs[].RetType` holds the ELEMENT kind
    for `function F: TArr`, so the aggregate was invisible to the return ABI:
    no hidden destination was allocated anywhere. Now recorded per-proc in
    ProcRetFixedArrBytes and asked through the ABI oracle.

  bug-a-set-and-array-function-results-come-back-empty }
program test_aggregate_function_results;
type
  TSet  = set of 0..31;
  TArr  = array[0..2] of Integer;
  TRec  = record a, b: Integer; end;
  TStr8 = string[8];

var g: TSet;

{ every way a set result can be produced }
function SLit: TSet;   begin SLit := [1, 4]; end;
function SLocal: TSet; var t: TSet; begin t := [1, 4]; SLocal := t; end;
function SGlob: TSet;  begin SGlob := g; end;
function SBuilt: TSet; begin SBuilt := []; SBuilt := SBuilt + [1] + [4]; end;
procedure SRef(var o: TSet); begin o := [1, 4]; end;

function MkArr: TArr;   begin MkArr[0] := 8; MkArr[1] := 9; MkArr[2] := 10; end;

{ the kinds that already worked, kept as controls }
function MkRec: TRec;  begin MkRec.a := 1; MkRec.b := 2; end;
function MkStr: TStr8; begin MkStr := 'made'; end;

var s: TSet; a: TArr; r: TRec; t: TStr8;
begin
  g := [1, 4];
  s := SLit;   WriteLn('set lit   ', 1 in s, ' ', 4 in s, ' ', 2 in s);
  s := SLocal; WriteLn('set local ', 1 in s, ' ', 4 in s);
  s := SGlob;  WriteLn('set glob  ', 1 in s, ' ', 4 in s);
  s := SBuilt; WriteLn('set built ', 1 in s, ' ', 4 in s);
  s := [];     SRef(s);
               WriteLn('set var   ', 1 in s, ' ', 4 in s);
  if 1 in SLit then WriteLn('set inline TRUE') else WriteLn('set inline FALSE');

  a := MkArr;  WriteLn('arr       ', a[0], ' ', a[1], ' ', a[2]);
  a[0] := 0; a[1] := 0; a[2] := 0;
  a := MkArr;  WriteLn('arr again ', a[0], ' ', a[1], ' ', a[2]);

  r := MkRec;  WriteLn('rec       ', r.a, ' ', r.b);
  t := MkStr;  WriteLn('str       ', t);
  WriteLn('AGGREGATE FUNCTION RESULTS OK');
end.
