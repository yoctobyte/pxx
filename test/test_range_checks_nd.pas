program rnd;
uses sysutils;
var m: array[1..2, 3..5] of integer; i, j: integer; caught: Integer;
begin
  caught := 0;
  m[1,3] := 7;
  {$R+}
  i := 3; j := 4;
  try m[i,j] := 1; writeln('w1 ok'); except on erangeerror do inc(caught); end;
  i := 1; j := 9;
  try m[i,j] := 1; writeln('w2 ok'); except on erangeerror do inc(caught); end;
  i := 2; j := 5;
  m[i,j] := 42;
  writeln('ok ', m[2,5], ' ', m[1,3], ' caught=', caught);
end.
