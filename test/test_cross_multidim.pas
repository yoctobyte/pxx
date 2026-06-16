program test_cross_multidim;
{ 2-D fixed arrays flattened to 1-D: both m[i,j] and m[i][j] index the same
  element; non-zero lower bounds; read + write. Byte-identical everywhere. }
var
  m: array[0..2, 0..3] of Integer;
  g: array[1..3, 1..2] of Int64;
  i, j, s: Integer;
  q: Int64;
begin
  for i := 0 to 2 do
    for j := 0 to 3 do
      m[i, j] := i * 10 + j;
  s := 0;
  for i := 0 to 2 do
    for j := 0 to 3 do
      s := s + m[i][j];           { read with bracket form }
  writeln('sum=', s, ' m12=', m[1, 2], ' m12b=', m[1][2]);
  m[2][3] := 99;                  { write with bracket form }
  writeln('m23=', m[2, 3]);

  for i := 1 to 3 do
    for j := 1 to 2 do
      g[i, j] := Int64(i) * 1000000000 + j;
  q := 0;
  for i := 1 to 3 do
    for j := 1 to 2 do
      q := q + g[i, j];
  writeln('gsum=', q, ' g32=', g[3, 2]);
end.
