program test_nested_dynarray_field;

{ SetLength on a nested sub-array slot reached through a record field —
  `SetLength(rec.matrix[i], n)` where matrix is `array of array of Integer`.
  The depth>=2 path keys off a root array symbol (works for a local `m[i]`), and
  the field path only handled a bare `rec.field`; an AN_INDEX into a nested-array
  field fell through and was rejected with "SetLength expects an array variable".
  Fix routes it through the slot-address path with leaf metadata from the base. }

type
  TGrid = record
    w: Integer;
    m: array of array of Integer;
  end;

var
  g: TGrid;
  i, j, sum: Integer;
begin
  g.w := 3;
  SetLength(g.m, 3);                  { outer dimension }
  for i := 0 to 2 do
  begin
    SetLength(g.m[i], 3);            { inner sub-array through the field — the fix }
    for j := 0 to 2 do g.m[i][j] := i * 10 + j;
  end;

  sum := 0;
  for i := 0 to 2 do
    for j := 0 to 2 do sum := sum + g.m[i][j];

  WriteLn('m00=', g.m[0][0], ' m12=', g.m[1][2], ' m22=', g.m[2][2], ' sum=', sum);
  { 0 12 22 ; sum = (0+1+2)+(10+11+12)+(20+21+22) = 3+33+63 = 99 }
end.
