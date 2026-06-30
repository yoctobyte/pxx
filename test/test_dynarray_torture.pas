program test_dynarray_torture;
{ Dynamic-array torture test (feature-dynarray-torture-test). Each case self-checks
  and prints `ok <n>` or `FAIL <n> ...`. The final line is the ok count, used as
  the oracle. Pins PXX's chosen semantics (deep-copy on assignment). Sections that
  hit a known gap are guarded/commented with a filed ticket reference. }

var
  okCount: Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;

{ ---- grow / shrink ---- }
procedure GrowShrink;
var a: array of Integer; i: Integer;
begin
  SetLength(a, 3);
  for i := 0 to 2 do a[i] := i + 10;
  Chk(1, (Length(a) = 3) and (a[0] = 10) and (a[2] = 12));
  SetLength(a, 5);                      { grow: contents preserved, new zeroed }
  Chk(2, (Length(a) = 5) and (a[0] = 10) and (a[2] = 12) and (a[3] = 0) and (a[4] = 0));
  SetLength(a, 2);                      { shrink: truncated }
  Chk(3, (Length(a) = 2) and (a[0] = 10) and (a[1] = 11));
  SetLength(a, 0);                      { empty }
  Chk(4, Length(a) = 0);
end;

{ ---- High / Low / empty / nil ---- }
procedure Bounds;
var a: array of Integer;
begin
  Chk(5, Length(a) = 0);                { unassigned dynarray = empty }
  Chk(6, High(a) = -1);                 { High of empty = -1 }
  SetLength(a, 4);
  Chk(7, (Low(a) = 0) and (High(a) = 3));
end;

{ ---- deep-copy semantics on assignment (PXX deep-copies) ---- }
procedure CopySemantics;
var a, b: array of Integer;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  b := a;                               { PXX: deep copy }
  b[0] := 99;
  Chk(8, (a[0] = 1) and (b[0] = 99));   { a unchanged => deep copy }
  Chk(9, (Length(b) = 3) and (b[1] = 2));
end;

{ ---- managed elements: dynarray of string ---- }
procedure StringElems;
var s: array of string; i: Integer; tot: Integer;
begin
  SetLength(s, 3);
  s[0] := 'aa'; s[1] := 'bbb'; s[2] := 'c';
  tot := 0;
  for i := 0 to 2 do tot := tot + Length(s[i]);
  Chk(10, tot = 6);
  SetLength(s, 5);                      { grow: old strings kept, new = '' }
  Chk(11, (s[0] = 'aa') and (s[4] = ''));
end;

{ ---- jagged / dynarray of dynarray ---- }
procedure Jagged;
var m: array of array of Integer; i, j, tot: Integer;
begin
  SetLength(m, 3);
  for i := 0 to 2 do
  begin
    SetLength(m[i], i + 1);             { ragged rows: 1,2,3 }
    for j := 0 to i do m[i][j] := (i + 1) * 10 + j;
  end;
  Chk(12, (Length(m) = 3) and (Length(m[0]) = 1) and (Length(m[2]) = 3));
  tot := 0;
  for i := 0 to 2 do for j := 0 to High(m[i]) do tot := tot + m[i][j];
  Chk(13, tot = (10) + (20 + 21) + (30 + 31 + 32));
end;

{ ---- dynarray of record with managed field ---- }
type
  TRec = record
    name: string;
    nums: array of Integer;
  end;

procedure RecordElems;
var r: array of TRec; i, tot: Integer;
begin
  SetLength(r, 2);
  r[0].name := 'x'; SetLength(r[0].nums, 2); r[0].nums[0] := 5; r[0].nums[1] := 6;
  r[1].name := 'yy'; SetLength(r[1].nums, 1); r[1].nums[0] := 7;
  tot := 0;
  for i := 0 to High(r[0].nums) do tot := tot + r[0].nums[i];
  Chk(14, (tot = 11) and (r[1].nums[0] = 7) and (Length(r[1].name) = 2));
end;

{ ---- passing: value / var / const / returned ---- }
function SumArr(a: array of Integer): Integer;
var i: Integer;
begin
  SumArr := 0;
  for i := 0 to High(a) do SumArr := SumArr + a[i];
end;

procedure FillVar(var a: array of Integer);
var i: Integer;
begin
  for i := 0 to High(a) do a[i] := i * 2;
end;

function MakeArr(n: Integer): array of Integer;
var i: Integer;
begin
  { bare function-name `MakeArr` as the dynarray result (FPC `F`=`Result`) —
    SetLength on it was rejected (undefined variable) until the 2026-06-30 fix. }
  SetLength(MakeArr, n);
  for i := 0 to n - 1 do MakeArr[i] := i + 1;
end;

procedure Passing;
var a: array of Integer;
begin
  SetLength(a, 4); a[0] := 1; a[1] := 2; a[2] := 3; a[3] := 4;
  Chk(15, SumArr(a) = 10);              { by-value open array }
  FillVar(a);
  Chk(16, (a[0] = 0) and (a[3] = 6));   { var open array mutates caller }
  a := MakeArr(5);                      { returned dynarray }
  Chk(17, (Length(a) = 5) and (SumArr(a) = 15));
end;

{ ---- class field dynarray ---- }
type
  TBox = class
    data: array of Integer;
    procedure Init(n: Integer);
    function Total: Integer;
  end;

procedure TBox.Init(n: Integer);
var i: Integer;
begin
  SetLength(data, n);                   { SetLength(Self.F, n) }
  for i := 0 to n - 1 do data[i] := i + 1;
end;

function TBox.Total: Integer;
var i: Integer;
begin
  Total := 0;
  for i := 0 to High(data) do Total := Total + data[i];
end;

procedure ClassField;
var b: TBox;
begin
  b := TBox.Create;
  b.Init(4);
  Chk(18, (Length(b.data) = 4) and (b.Total = 10));
  b.Free;
end;

{ ---- stress: many grow/shrink cycles, large realloc ---- }
procedure Stress;
var a: array of Integer; i, cyc, bad: Integer;
begin
  bad := 0;
  for cyc := 1 to 50 do
  begin
    SetLength(a, cyc * 100);
    a[0] := cyc; a[cyc * 100 - 1] := cyc * 7;
    if (a[0] <> cyc) or (a[cyc * 100 - 1] <> cyc * 7) then bad := bad + 1;
    SetLength(a, 1);
    if a[0] <> cyc then bad := bad + 1;  { element 0 preserved across shrink }
  end;
  Chk(19, bad = 0);
end;

{ ---- for-in over a dynarray ---- }
procedure ForIn;
var a: array of Integer; x, tot: Integer;
begin
  SetLength(a, 4); a[0] := 2; a[1] := 4; a[2] := 6; a[3] := 8;
  tot := 0;
  for x in a do tot := tot + x;
  Chk(20, tot = 20);
end;

{ ---- Copy(arr, i, n) sub-array ---- }
procedure CopySub;
var a, b: array of Integer; i: Integer;
begin
  SetLength(a, 5);
  for i := 0 to 4 do a[i] := i + 1;
  b := Copy(a, 1, 3);
  Chk(21, (Length(b) = 3) and (b[0] = 2) and (b[2] = 4));
  a[1] := 99;                           { Copy is independent }
  Chk(22, b[0] = 2);
end;

{ ---- record-by-value copy deep-copies its dynarray field ---- }
procedure RecCopy;
var x, y: TRec;
begin
  SetLength(x.nums, 3); x.nums[0] := 1; x.nums[1] := 2; x.nums[2] := 3;
  y := x;                               { PXX deep-copies the dynarray field }
  y.nums[0] := 99;
  Chk(23, (x.nums[0] = 1) and (y.nums[0] = 99));
end;

{ ---- element passed as a var actual ---- }
procedure Bump(var v: Integer);
begin v := v + 100; end;

procedure ElemVar;
var a: array of Integer;
begin
  SetLength(a, 3); a[1] := 5;
  Bump(a[1]);
  Chk(24, a[1] = 105);
end;

{ ---- one-call multidim SetLength(a, d1, d2[, d3]) ---- }
procedure MultiDim;
var a: array of array of Integer; b: array of array of array of Integer;
    i, j, k, tot: Integer;
begin
  SetLength(a, 2, 3);                    { rectangular 2x3 }
  Chk(25, (Length(a) = 2) and (Length(a[0]) = 3) and (Length(a[1]) = 3));
  for i := 0 to 1 do for j := 0 to 2 do a[i][j] := i * 10 + j;
  Chk(26, (a[1][2] = 12) and (a[0][0] = 0));
  SetLength(b, 2, 3, 4);                 { 3-D }
  tot := 0;
  for i := 0 to High(b) do for j := 0 to High(b[i]) do for k := 0 to High(b[i][j]) do
    tot := tot + 1;
  Chk(27, (Length(b) = 2) and (Length(b[0]) = 3) and (Length(b[0][0]) = 4) and (tot = 24));
end;

begin
  okCount := 0;
  GrowShrink;
  Bounds;
  CopySemantics;
  StringElems;
  Jagged;
  RecordElems;
  Passing;
  ClassField;
  Stress;
  ForIn;
  CopySub;
  RecCopy;
  ElemVar;
  MultiDim;
  writeln('total ok ', okCount, ' / 27');
end.
