{ A ROW of a multi-dimensional Char array is a string, in BOTH directions.

  `a[0] := 'hi'` was refused as `cannot assign ShortString to Char`; that was
  the reported half. The LOAD direction was worse and unreported: `s := a[0]`
  compiled, exited 0, and assigned ONE character -- `x` where fpc gives `xyz!`.
  A refusal is a bug you can see. This one you can only measure.

  Rows 1-3 are the three SPELLINGS of the same store: `array[0..2, 0..5]`,
  `array[0..2] of array[0..5]`, and `array[0..2] of R` for a named R. They
  flatten identically, so a fix keyed on any one of them would leave the others,
  and they are here to say the key is the SHAPE and not the syntax.

  Rows 4-5 are the two BASES this arm accepts -- a plain variable and a record
  field -- inherited from NDRowSourceInfo rather than re-derived here, which is
  what those rows say.

  Rows 6-7 are the THIRD base, a pointer DEREF, and they carry the history that
  kept them out of this file for a day. Measured then, `q^[1]` loaded three
  characters where fpc loads six while `q^[0]` loaded all six, which reads
  exactly like a load bug one row-index deep -- so the arm was refused rather
  than shipped with a plausible wrong answer. It was not a load bug. `New(q)`
  sized the block by the ELEMENT kind, so the 18-byte pointee got one byte
  rounded to sixteen and row 1 read `103 104 32 0 0 0`. Both rows are here
  BECAUSE that is the shape that lied: a defect in the allocator wearing the
  costume of a defect in the reader.

  The two deref rows are a HEAP pointee (`New(heap)`) and a STACK one
  (`stk := @grid`) for that reason -- the first is the one that was corrupt and
  the second never was, so they fail differently.

  The last row is the NEGATIVE control and it is the load-bearing one: `b[0]`
  on a 3-D array names a 2-D SUB-ARRAY, not a row, and fpc refuses a string
  there. The
  capacity NDRowSourceInfo would return for it -- the product of the trailing
  dimensions -- is a plausible number and the wrong one, and using it would
  write past the row. It reads an ELEMENT of that sub-array instead, which is
  what a program may legally do, so the row still asserts a value.

  Every row is fpc 3.2.2's own output, byte for byte. }
program test_char_array_nd_row_is_a_string;

type
  R6 = array[0..5] of Char;
  G26 = array[0..2, 0..5] of Char;
  PG26 = ^G26;
  TRec = record
    grid : array[0..2, 0..5] of Char;
  end;

var
  comma  : array[0..2, 0..5] of Char;
  ofarr  : array[0..2] of array[0..5] of Char;
  named  : array[0..2] of R6;
  rec    : TRec;
  cube   : array[0..1, 0..1, 0..3] of Char;
  grid   : G26;
  heap   : PG26;
  stk    : PG26;
  s      : ShortString;
  i, j, k: Integer;

begin
  comma[0] := 'hi';
  writeln('store  comma spelling : [', comma[0], ']');

  ofarr[1] := 'hi';
  writeln('store  of-array spell : [', ofarr[1], ']');

  named[2] := 'hi';
  writeln('store  named elem type: [', named[2], ']');

  for i := 0 to 2 do
    for j := 0 to 5 do
      comma[i][j] := Chr(Ord('a') + i * 6 + j);
  s := comma[1];
  writeln('load   into a string  : [', s, ']');

  for i := 0 to 2 do
    for j := 0 to 5 do
      rec.grid[i][j] := Chr(Ord('A') + i * 6 + j);
  s := rec.grid[2];
  writeln('load   through a field: [', s, ']');

  writeln('compare row to a lit  : ', comma[0] = 'abcdef');

  New(heap);
  for i := 0 to 2 do
    for j := 0 to 5 do
      heap^[i][j] := Chr(Ord('a') + i * 6 + j);
  s := heap^[1];
  writeln('load   through New    : [', s, ']');
  Dispose(heap);

  stk := @grid;
  for i := 0 to 2 do
    for j := 0 to 5 do
      grid[i][j] := Chr(Ord('A') + i * 6 + j);
  s := stk^[2];
  writeln('load   through @stack : [', s, ']');

  for i := 0 to 1 do
    for j := 0 to 1 do
      for k := 0 to 3 do
        cube[i][j][k] := Chr(Ord('p') + i * 8 + j * 4 + k);
  writeln('CONTROL 3-D sub-array : [', cube[1][1][2], ']');
end.
