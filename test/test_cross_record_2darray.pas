program test_cross_record_2darray;
{ 2-D fixed-array fields in a record: r.m[i,j] and r.m[i][j], read+write, mixed
  with other fields and an Int64 2-D field. Byte-identical on every target. }
type
  TR = record
    m: array[0..2, 0..3] of Integer;
    g: array[1..2, 1..2] of Int64;
    tag: Integer;
  end;
var r: TR; i, j, s: Integer; q: Int64;
begin
  for i := 0 to 2 do for j := 0 to 3 do r.m[i, j] := i * 10 + j;
  r.tag := 7;
  s := 0; for i := 0 to 2 do for j := 0 to 3 do s := s + r.m[i][j];
  writeln('msum=', s, ' m23=', r.m[2, 3], ' tag=', r.tag);
  r.m[1][1] := 99;
  writeln('m11=', r.m[1, 1]);
  for i := 1 to 2 do for j := 1 to 2 do r.g[i, j] := Int64(i) * 1000000000 + j;
  q := 0; for i := 1 to 2 do for j := 1 to 2 do q := q + r.g[i, j];
  writeln('gsum=', q, ' g22=', r.g[2, 2]);
end.
