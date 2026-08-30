program test_index_a_call_result_directly;
{ Indexing the RESULT of a call directly, without an intermediate variable.
  Every row below is FPC-differential: test_index_a_call_result_directly.expected
  was produced by FPC compiling THIS FILE, not written by hand.

  feature-a-index-an-array-returning-call-directly
  compat-pascal-index-a-function-call-result }
type
  TArr   = array[0..2] of Integer;
  TArr2  = array[0..1, 0..2] of Integer;
  TStrs  = array[0..2] of string[8];     { FROZEN-string element }
  TMStrs = array[0..2] of AnsiString;    { MANAGED-string element }
  TMStr2 = array[0..1, 0..1] of AnsiString;
  TRecX  = record a: Integer; b: string[4]; end;
  TRA    = array[0..2] of TRecX;
  TRA2   = array[0..1, 0..1] of TRecX;

var Calls: Integer;

function MkS: string;
begin Inc(Calls); MkS := 'hello'; end;

function MkArr: TArr;
begin Inc(Calls); MkArr[0] := 10; MkArr[1] := 20; MkArr[2] := 30; end;

function MkArr2: TArr2;
var i, j: Integer;
begin
  Inc(Calls);
  for i := 0 to 1 do for j := 0 to 2 do MkArr2[i, j] := i * 10 + j;
end;

function MkStr: TStrs;
begin Inc(Calls); MkStr[0] := 'lo'; MkStr[1] := 'mid'; MkStr[2] := 'hi'; end;

{ The MANAGED-string element. Procs[].RetType carries the ELEMENT kind, so this
  reads as tyAnsiString at the suffix parser and used to take the
  index-a-string-VALUE arm -- the whole array materialised into an AnsiString
  temp and indexed 1-based by the byte, answering Length 1 and one garbage
  character. The FROZEN row above could not catch it: string[8] is tyFixedString
  there and never entered that arm.
  bug-a-indexing-a-function-result-that-is-an-array-of-managed-strings-yields-garbage }
function MkMStr: TMStrs;
begin Inc(Calls); MkMStr[0] := 'alpha'; MkMStr[1] := 'beta'; MkMStr[2] := 'gamma'; end;

function MkMStr2: TMStr2;
var i, j: Integer;
begin
  Inc(Calls);
  for i := 0 to 1 do for j := 0 to 1 do MkMStr2[i, j] := Chr(Ord('a') + i) + Chr(Ord('0') + j);
end;

function MkR: TRA;
begin Inc(Calls); MkR[0].a := 7; MkR[1].a := 8; MkR[1].b := 'eight'; MkR[2].a := 9; end;

function MkR2: TRA2;
var i, j: Integer;
begin
  Inc(Calls);
  for i := 0 to 1 do for j := 0 to 1 do MkR2[i, j].a := i * 10 + j;
end;

var i: Integer; s: string;
begin
  Calls := 0;
  WriteLn('str  ', MkS[2]);
  WriteLn('arr  ', MkArr[1]);
  WriteLn('nd   ', MkArr2[1, 2]);
  WriteLn('ndbr ', MkArr2[1][2]);
  WriteLn('froz ', MkStr[1]);          { must be `mid`, not the length word }
  WriteLn('mgd  ', MkMStr[1]);         { must be `beta`, not one garbage char }
  WriteLn('mgdln', Length(MkMStr[0])); { must be 5, not 1 }
  WriteLn('mgdnd', MkMStr2[1, 0]);
  WriteLn('mgdbr', MkMStr2[1][0]);
  WriteLn('rec  ', MkR[1].a);
  WriteLn('recs ', MkR[1].b);
  WriteLn('ndrec', MkR2[1, 1].a);
  WriteLn('ndrbr', MkR2[1][1].a);
  { a computed subscript, and the call evaluated EXACTLY ONCE per index }
  i := 2;
  WriteLn('var  ', MkArr[i]);
  WriteLn('calls', Calls);
  { the BUILTIN-intrinsic spelling: Copy's parse branch used to Exit straight
    past the postfix chain, so `Nm()[1]` and `Copy(s,2,3)[1]` disagreed despite
    both being a string indexed off a call }
  s := 'hello';
  WriteLn('copy ', Copy(s, 2, 3)[1]);
  WriteLn('copy2', Copy(s, 2, 3)[3]);
end.
