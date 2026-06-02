program test_nested_dynarray;

{ Nested dynamic arrays of scalar element types: array of array [of array] of T.
  Each level is an independent heap block of pointer-sized sub-array handles
  (deepest level holds base elements). SetLength works on the outer array and on
  any sub-array element; Length reads the per-level header; sub-arrays are
  released recursively on scope exit. No copy-on-write at nested levels. }

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  m: array of array of Integer;
  t: array of array of array of Integer;
  i, j, k, sum: Integer;

{ Local nested array — exercises recursive scope-exit release. }
procedure FillLocal;
var c: array of array of Integer; a, b: Integer;
begin
  SetLength(c, 3);
  for a := 0 to 2 do
  begin
    SetLength(c[a], 2);
    for b := 0 to 1 do
      c[a][b] := a * 2 + b;
  end;
  Check(c[2][1] = 5);
end;

begin
  { Jagged depth-2 array. }
  SetLength(m, 3);
  Check(Length(m) = 3);
  SetLength(m[0], 2);
  SetLength(m[1], 4);
  SetLength(m[2], 1);
  Check(Length(m[0]) = 2);
  Check(Length(m[1]) = 4);
  Check(Length(m[2]) = 1);

  for i := 0 to 2 do
    for j := 0 to Length(m[i]) - 1 do
      m[i][j] := i * 10 + j;

  Check(m[0][0] = 0);
  Check(m[0][1] = 1);
  Check(m[1][3] = 13);
  Check(m[2][0] = 20);

  sum := 0;
  for i := 0 to 2 do
    for j := 0 to Length(m[i]) - 1 do
      sum := sum + m[i][j];
  Check(sum = (0 + 1) + (10 + 11 + 12 + 13) + 20);

  { Grow a sub-array; preserved prefix keeps its values, new slots are zero. }
  SetLength(m[0], 4);
  Check(Length(m[0]) = 4);
  Check(m[0][0] = 0);
  Check(m[0][1] = 1);
  Check(m[0][3] = 0);

  { Depth-3 array. }
  SetLength(t, 2);
  for i := 0 to 1 do
  begin
    SetLength(t[i], 2);
    for j := 0 to 1 do
      SetLength(t[i][j], 2);
  end;
  for i := 0 to 1 do
    for j := 0 to 1 do
      for k := 0 to 1 do
        t[i][j][k] := i * 100 + j * 10 + k;
  Check(t[0][0][0] = 0);
  Check(t[1][0][1] = 101);
  Check(t[1][1][1] = 111);

  FillLocal;
  FillLocal;
end.
