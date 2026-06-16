program test_cross_param_2darray;
{ Named fixed-array type parameters: 1-D and 2-D, const (read) and var (mutate
  the caller's array). Previously a named-array param was scalar (garbage) and
  2-D failed to parse. Byte-identical on every target. }
type
  TVec = array[0..3] of Integer;
  TGrid = array[0..2, 0..3] of Integer;
function SumVec(const a: TVec): Integer;
var i, s: Integer;
begin s := 0; for i := 0 to 3 do s := s + a[i]; SumVec := s; end;
function SumGrid(const g: TGrid): Integer;
var i, j, s: Integer;
begin s := 0; for i := 0 to 2 do for j := 0 to 3 do s := s + g[i, j]; SumGrid := s; end;
procedure FillGrid(var g: TGrid; base: Integer);
var i, j: Integer;
begin for i := 0 to 2 do for j := 0 to 3 do g[i][j] := base + i * 10 + j; end;
var v: TVec; m: TGrid; i, j: Integer;
begin
  for i := 0 to 3 do v[i] := i * i;
  writeln('vsum=', SumVec(v));
  for i := 0 to 2 do for j := 0 to 3 do m[i, j] := i + j;
  writeln('gsum=', SumGrid(m));
  FillGrid(m, 100);              { var param mutates m }
  writeln('after=', SumGrid(m), ' m23=', m[2, 3]);
end.
