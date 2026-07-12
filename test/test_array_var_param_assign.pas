program test_array_var_param_assign;
{ bug-array-assign-to-var-param: a whole-array assignment TO a `var` array
  parameter sized its IR_COPY_REC from Syms[].ArrLen, which for ANY array param
  was AllocParam's open-array placeholder (1000) rather than the named type's
  real length. `r := tmp` on a 4-element array therefore copied 1000 elements
  over the caller's frame -> segfault (or silent corruption, if the overrun
  happened to land on mapped memory).

  Covers: element widths, record elements, aliasing, N-D, and that a genuine
  open array (whose length really is unknown) is left alone. }

type
  TI4 = array[0..3] of Integer;
  TQ4 = array[0..3] of UInt64;
  TL3 = array[0..2] of Int64;
  TPt = record x, y: Integer; end;
  TR2 = array[0..1] of TPt;
  TM   = array[0..1, 0..2] of Integer;   { N-D: flattened length 6 }

var
  fails: Integer;

procedure Bump(var r: TI4; const a: TI4);
var tmp: TI4; i: Integer;
begin
  for i := 0 to 3 do tmp[i] := a[i] + 1;
  r := tmp;                    { the bug }
end;

procedure BumpQ(var r: TQ4; const a: TQ4);
var tmp: TQ4; i: Integer;
begin
  for i := 0 to 3 do tmp[i] := a[i] + 1;
  r := tmp;
end;

procedure BumpL(var r: TL3; const a: TL3);
var tmp: TL3; i: Integer;
begin
  for i := 0 to 2 do tmp[i] := a[i] + 1;
  r := tmp;
end;

procedure BumpR(var r: TR2; const a: TR2);
var tmp: TR2; i: Integer;
begin
  for i := 0 to 1 do
  begin
    tmp[i].x := a[i].x + 1;
    tmp[i].y := a[i].y + 1;
  end;
  r := tmp;
end;

procedure BumpM(var r: TM; const a: TM);
var tmp: TM; i, j: Integer;
begin
  for i := 0 to 1 do
    for j := 0 to 2 do
      tmp[i][j] := a[i][j] + 1;
  r := tmp;
end;

{ destination aliased with the source }
procedure BumpSelf(var r: TI4);
var tmp: TI4; i: Integer;
begin
  for i := 0 to 3 do tmp[i] := r[i] * 2;
  r := tmp;
end;

{ a genuine open array still has an unknown length; only reads/writes per
  element are meaningful, and it must keep working }
function SumOpen(const a: array of Integer): Integer;
var i, s: Integer;
begin
  s := 0;
  for i := 0 to High(a) do s := s + a[i];
  SumOpen := s;
end;

procedure Fail(const what: AnsiString);
begin
  WriteLn('FAIL ', what);
  Inc(fails);
end;

var
  x, y: TI4;
  qx, qy: TQ4;
  lx, ly: TL3;
  rx, ry: TR2;
  mx, my: TM;
  guardBefore, guardAfter: Int64;
  i, j: Integer;

begin
  fails := 0;

  { guards straddle the arrays on the frame: a 1000-element overrun would
    stomp them long before it faulted }
  guardBefore := Int64($5A5A5A5A5A5A5A5A);
  guardAfter  := Int64($A5A5A5A5A5A5A5A5);

  for i := 0 to 3 do x[i] := i * 10;
  Bump(y, x);
  for i := 0 to 3 do
    if y[i] <> i * 10 + 1 then Fail('Integer elements');

  for i := 0 to 3 do qx[i] := UInt64(i) * 1000000000000;
  BumpQ(qy, qx);
  for i := 0 to 3 do
    if qy[i] <> UInt64(i) * 1000000000000 + 1 then Fail('UInt64 elements');

  for i := 0 to 2 do lx[i] := Int64(i) * 5;
  BumpL(ly, lx);
  for i := 0 to 2 do
    if ly[i] <> Int64(i) * 5 + 1 then Fail('Int64 elements');

  for i := 0 to 1 do
  begin
    rx[i].x := i;
    rx[i].y := i * 2;
  end;
  BumpR(ry, rx);
  for i := 0 to 1 do
    if (ry[i].x <> i + 1) or (ry[i].y <> i * 2 + 1) then Fail('record elements');

  for i := 0 to 1 do
    for j := 0 to 2 do
      mx[i][j] := i * 3 + j;
  BumpM(my, mx);
  for i := 0 to 1 do
    for j := 0 to 2 do
      if my[i][j] <> i * 3 + j + 1 then Fail('N-D elements');

  { aliased destination }
  for i := 0 to 3 do x[i] := i + 1;
  BumpSelf(x);
  for i := 0 to 3 do
    if x[i] <> (i + 1) * 2 then Fail('aliased dest');

  { open array untouched by the fix }
  if SumOpen(y) <> (1 + 11 + 21 + 31) then Fail('open array');

  if guardBefore <> Int64($5A5A5A5A5A5A5A5A) then Fail('frame guard before clobbered');
  if guardAfter <> Int64($A5A5A5A5A5A5A5A5) then Fail('frame guard after clobbered');

  if fails = 0 then WriteLn('ARRAY VAR PARAM ASSIGN OK')
  else WriteLn('ARRAY VAR PARAM ASSIGN FAIL (', fails, ')');
end.
