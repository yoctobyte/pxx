program test_cross_multidim3d;
{ 3-D (and N-D) fixed arrays: variable, named type, record field, and parameter;
  both m[i,j,k] and m[i][j][k] index syntaxes; read + write; Int64 element.
  Flattened to 1-D, so byte-identical on every target. }
type
  TCube = array[0..1, 0..2, 0..3] of Integer;
var
  c: array[0..1, 0..2, 0..3] of Int64;
function CubeSum(const q: TCube): Integer;
var i, j, k, s: Integer;
begin
  s := 0;
  for i := 0 to 1 do for j := 0 to 2 do for k := 0 to 3 do s := s + q[i, j, k];
  CubeSum := s;
end;
procedure FillCube(var q: TCube);
var i, j, k: Integer;
begin
  for i := 0 to 1 do for j := 0 to 2 do for k := 0 to 3 do q[i][j][k] := i * 100 + j * 10 + k;
end;
type TR = record cube: array[0..1, 0..1, 0..1] of Integer; tag: Integer; end;
var named: TCube; r: TR; i, j, k, s: Integer; q: Int64;
begin
  for i := 0 to 1 do for j := 0 to 2 do for k := 0 to 3 do c[i, j, k] := Int64(i * 100 + j * 10 + k) * 1000000;
  q := 0;
  for i := 0 to 1 do for j := 0 to 2 do for k := 0 to 3 do q := q + c[i][j][k];
  writeln('var3d=', q, ' c123=', c[1, 2, 3]);
  FillCube(named);
  writeln('param3d=', CubeSum(named), ' n123=', named[1, 2, 3]);
  for i := 0 to 1 do for j := 0 to 1 do for k := 0 to 1 do r.cube[i, j, k] := i * 4 + j * 2 + k;
  r.tag := 9;
  s := 0; for i := 0 to 1 do for j := 0 to 1 do for k := 0 to 1 do s := s + r.cube[i][j][k];
  writeln('field3d=', s, ' rc=', r.cube[1, 1, 1], ' tag=', r.tag);
end.
