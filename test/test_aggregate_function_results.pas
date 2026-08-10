{ Function results of the AGGREGATE kinds, every line diffed against FPC.

  Two silently wrong answers, both pre-existing and both found by that diff:

  * a SET-returning function answered the EMPTY set, whatever its body did, on
    every target. `FuncName := [1, 4]` leaves the LHS ASTTk unset, so the set
    arm — which tested the node type only — missed it and the scalar store path
    wrote the literal's ADDRESS into the 32-byte Result slot. The record arm
    beside it already carried the symbol-TypeKind fallback for exactly this; the
    set arm was the sibling that never got it.

  * a FIXED-ARRAY-returning function answered element 0 and zeros
    (`8 9 10` came back as `8 0 0`). `Procs[].RetType` holds the ELEMENT kind
    for `function F: TArr`, so the aggregate was invisible to the return ABI:
    no hidden destination was allocated anywhere. Now recorded per-proc in
    ProcRetFixedArrBytes and asked through the ABI oracle.

  bug-a-set-and-array-function-results-come-back-empty

  Then the Result SLOT itself, which was allocated by AllocVar as ONE element
  of the element type — no array shape, no dim spans, one element's worth of
  frame. Three symptoms, one missing stamp
  (bug-a-nd-array-function-result-indexes-the-wrong-slot):

  * `array[0..2]` survived on frame padding; `array[0..3]` reached the saved
    return address and SIGSEGVed — which is why the row below is 4 elements.
  * an N-D result carried no dim spans, so the callee's own `M[0,1] := 2`
    linearised to the wrong slot: 1 2 3 4 read back as 1 3 3 4.
  * the element kind came from ParseTypeKind, which does not know the ArrType
    table and answered tyInteger for every alias — right by accident for
    `array of Integer`, an Integer-strided Result for `array of string[8]`
    and `array of TRec`.

  Every row here is diffed against FPC. }
program test_aggregate_function_results;
type
  TSet  = set of 0..31;
  TArr  = array[0..2] of Integer;
  TArr4 = array[0..3] of Integer;         { 4 elements: reaches the return address }
  TArr2 = array[0..1, 0..1] of Integer;   { N-D: needs the dim spans }
  TArr3 = array[1..2, 0..2, 5..6] of Integer;  { 3-D, non-zero lo bounds }
  TRec  = record a, b: Integer; end;
  TStr8 = string[8];
  TArrS = array[0..2] of TStr8;           { element kind is not Integer }
  TArrR = array[0..1, 0..1] of TRec;      { …nor here }

var g: TSet;

{ every way a set result can be produced }
function SLit: TSet;   begin SLit := [1, 4]; end;
function SLocal: TSet; var t: TSet; begin t := [1, 4]; SLocal := t; end;
function SGlob: TSet;  begin SGlob := g; end;
function SBuilt: TSet; begin SBuilt := []; SBuilt := SBuilt + [1] + [4]; end;
procedure SRef(var o: TSet); begin o := [1, 4]; end;

function MkArr: TArr;   begin MkArr[0] := 8; MkArr[1] := 9; MkArr[2] := 10; end;

{ the Result-slot rows. MkArr4 keeps a guard local so a frame overrun shows up
  as a wrong value and not only as a crash. }
function MkArr4: TArr4;
var guard: Integer;
begin
  guard := 77;
  MkArr4[0] := 1; MkArr4[1] := 2; MkArr4[2] := 3; MkArr4[3] := 4;
  if guard <> 77 then WriteLn('GUARD CLOBBERED ', guard);
end;
function MkArr2: TArr2;
begin MkArr2[0,0] := 1; MkArr2[0,1] := 2; MkArr2[1,0] := 3; MkArr2[1,1] := 4; end;
function MkArr3: TArr3;
var i, j, k: Integer;
begin
  for i := 1 to 2 do for j := 0 to 2 do for k := 5 to 6 do
    MkArr3[i,j,k] := i*100 + j*10 + k;
end;
function MkArrS: TArrS;
begin MkArrS[0] := 'aa'; MkArrS[1] := 'bb'; MkArrS[2] := 'cc'; end;
function MkArrR: TArrR;
begin
  MkArrR[0,0].a := 1; MkArrR[0,0].b := 2;
  MkArrR[1,1].a := 3; MkArrR[1,1].b := 4;
end;

{ the kinds that already worked, kept as controls }
function MkRec: TRec;  begin MkRec.a := 1; MkRec.b := 2; end;
function MkStr: TStr8; begin MkStr := 'made'; end;

var s: TSet; a: TArr; r: TRec; t: TStr8;
    a4: TArr4; a2: TArr2; a3: TArr3; aS: TArrS; aR: TArrR;
    i, j, k: Integer;
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

  a4 := MkArr4; WriteLn('arr4      ', a4[0], ' ', a4[1], ' ', a4[2], ' ', a4[3]);
  a2 := MkArr2; WriteLn('arr 2d    ', a2[0,0], ' ', a2[0,1], ' ', a2[1,0], ' ', a2[1,1]);
  a3 := MkArr3; Write('arr 3d   ');
  for i := 1 to 2 do for j := 0 to 2 do for k := 5 to 6 do Write(' ', a3[i,j,k]);
  WriteLn;
  aS := MkArrS; WriteLn('arr str   ', aS[0], ' ', aS[1], ' ', aS[2]);
  aR := MkArrR; WriteLn('arr rec   ', aR[0,0].a, ' ', aR[0,0].b, ' ',
                                      aR[1,1].a, ' ', aR[1,1].b);

  r := MkRec;  WriteLn('rec       ', r.a, ' ', r.b);
  t := MkStr;  WriteLn('str       ', t);
  WriteLn('AGGREGATE FUNCTION RESULTS OK');
end.
