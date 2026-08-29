program nested_slice;
{ Nested dynamic arrays: IR_SETLEN_DYN and IR_DYNUNIQUE.

  These two cannot be tested apart — a nested row has to be SetLength'd before
  it can be indexed, and every probe for one refused on the other first.

  The row that matters most is `SetLength(m, n)` on an array whose elements are
  themselves arrays. It does NOT take the flat -102 builtin path: it lowers to
  IR_SETLEN_DYN with an IR_LEA target, and IR_LEA on a dynamic array AUTO-LOADS
  to the data pointer, while PXXDynSetLen needs the SLOT and reads a nil handle
  as "nothing to do". Get that wrong and the array stays empty, every body
  lowers, the module validates and Length answers 0. }
type
  TM = array of array of Integer;
  TT = array of array of array of Integer;
var
  m: TM; t: TT; i, j, k, n: Integer;
begin
  SetLength(m, 3);
  writeln('outer len=', Length(m));
  for i := 0 to 2 do
  begin
    SetLength(m[i], 4);
    for j := 0 to 3 do m[i][j] := i * 10 + j;
  end;
  writeln('read  ', m[0][0], ' ', m[1][2], ' ', m[2][3]);

  { rows of DIFFERENT lengths — a single shared stride would still pass the
    uniform case above }
  SetLength(m[1], 7);
  writeln('ragged len=', Length(m), ' m10=', m[1][0]);
  m[1][6] := 99;
  writeln('ragged tail=', m[1][6], ' neighbour=', m[2][3]);

  { three levels, so IR_DYNUNIQUE recurses through its own output }
  SetLength(t, 2);
  for i := 0 to 1 do
  begin
    SetLength(t[i], 2);
    for j := 0 to 1 do
    begin
      SetLength(t[i][j], 2);
      for k := 0 to 1 do t[i][j][k] := i * 100 + j * 10 + k;
    end;
  end;
  writeln('deep  ', t[0][0][0], ' ', t[1][0][1], ' ', t[1][1][1]);

  { grow an existing row: the old contents must survive }
  SetLength(m, 5);
  writeln('grow  len=', Length(m), ' kept=', m[0][0], ' ', m[1][6]);

  n := 0;
  for i := 0 to 2 do for j := 0 to 3 do n := n + m[i][j];
  writeln('sum   ', n);
  writeln('done');
end.
