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

  A DEREF base is NOT here, and its absence is measured rather than assumed:
  `q^[1]` over `^array[0..2, 0..5] of Char` stores correctly (byte-identical to
  fpc) and LOADS three characters where fpc loads six, while `q^[0]` loads all
  six -- a second defect on the load path that this predicate does not reach.
  At HEAD both rows loaded one character. Admitting it would trade a wrong
  answer for a more plausible one, so it stays refused and is filed:
  bug-p-a-char-array-row-through-a-pointer-deref-loads-short.

  Row 7 is the NEGATIVE control and it is the load-bearing one: `b[0]` on a 3-D
  array names a 2-D SUB-ARRAY, not a row, and fpc refuses a string there. The
  capacity NDRowSourceInfo would return for it -- the product of the trailing
  dimensions -- is a plausible number and the wrong one, and using it would
  write past the row. It reads an ELEMENT of that sub-array instead, which is
  what a program may legally do, so the row still asserts a value.

  Every row is fpc 3.2.2's own output, byte for byte. }
program test_char_array_nd_row_is_a_string;

type
  R6 = array[0..5] of Char;
  TRec = record
    grid : array[0..2, 0..5] of Char;
  end;

var
  comma  : array[0..2, 0..5] of Char;
  ofarr  : array[0..2] of array[0..5] of Char;
  named  : array[0..2] of R6;
  rec    : TRec;
  cube   : array[0..1, 0..1, 0..3] of Char;
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

  for i := 0 to 1 do
    for j := 0 to 1 do
      for k := 0 to 3 do
        cube[i][j][k] := Chr(Ord('p') + i * 8 + j * 4 + k);
  writeln('CONTROL 3-D sub-array : [', cube[1][1][2], ']');
end.
