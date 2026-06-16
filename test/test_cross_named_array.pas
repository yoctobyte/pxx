program test_cross_named_array;
{ Named fixed-array types (1-D and 2-D) used by a variable. Previously the type
  def was skipped, so `var a: TA` was not an array (silent wrong). Byte-identical
  on every target. }
type
  TVec = array[0..4] of Integer;
  TGrid = array[0..2, 0..3] of Integer;
  TBig = array[1..3] of Int64;
var v: TVec; g: TGrid; b: TBig; i, j, s: Integer; q: Int64;
begin
  for i := 0 to 4 do v[i] := i * i;
  s := 0; for i := 0 to 4 do s := s + v[i];
  writeln('vsum=', s);
  for i := 0 to 2 do for j := 0 to 3 do g[i, j] := i * 10 + j;
  s := 0; for i := 0 to 2 do for j := 0 to 3 do s := s + g[i][j];
  writeln('gsum=', s, ' g23=', g[2, 3]);
  for i := 1 to 3 do b[i] := Int64(i) * 1000000000;
  q := 0; for i := 1 to 3 do q := q + b[i];
  writeln('bsum=', q);
end.
