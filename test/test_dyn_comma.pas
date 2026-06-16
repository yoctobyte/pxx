program test_cross_dyn_comma;
{ Comma subscript sugar m[i,j] on jagged (dynamic) arrays — same as the bracket
  form m[i][j], incl. a named alias. x86-64 (nested dynamic SetLength is x86-64-only on cross backends). }
type TMat = array of array of Integer;
var m: array of array of Integer; t: TMat; i, j, s: Integer;
begin
  SetLength(m, 3);
  for i := 0 to 2 do SetLength(m[i], 4);
  for i := 0 to 2 do for j := 0 to 3 do m[i, j] := i * 10 + j;
  s := 0; for i := 0 to 2 do for j := 0 to 3 do s := s + m[i, j];
  writeln('m=', s, ' m12=', m[1, 2], ' brk=', m[1][2]);
  SetLength(t, 2);
  for i := 0 to 1 do SetLength(t[i], 3);
  for i := 0 to 1 do for j := 0 to 2 do t[i, j] := i + j;
  s := 0; for i := 0 to 1 do for j := 0 to 2 do s := s + t[i, j];
  writeln('alias=', s, ' t11=', t[1, 1]);
end.
