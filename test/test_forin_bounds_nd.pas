program test_forin_bounds_nd;
{ for-in over a static array iterates the array's OWN index range (array[1..3],
  array[5..7] read shifted garbage before), and an N-D static array iterates
  its OUTER dimension by row (it ran the FLATTENED count of garbage rows).
  bug-pascal-forin-variants-wrong-output. }
type T = array[1..3] of Integer;
var
  r1: array[1..3] of Integer; z: array[5..7] of Integer;
  a: array[0..1] of T; row: T;
  i: Integer;
begin
  r1[1] := 10; r1[2] := 20; r1[3] := 30;
  for i in r1 do write(i, ' '); writeln;
  z[5] := 50; z[6] := 60; z[7] := 70;
  for i in z do write(i, ' '); writeln;
  a[0][1] := 1; a[0][2] := 2; a[0][3] := 9;
  a[1][1] := 3; a[1][2] := 4; a[1][3] := 5;
  for row in a do
  begin
    for i in row do write(i, ' ');
    writeln;
  end;
end.
