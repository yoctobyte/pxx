{ `for s in c` over `array[1..3, 1..3] of Char` printed `a d g` where fpc
  prints `abc def ghi` -- the first character of each row, three times, exit 0.
  Silent, and the row it came from (tforin12) is EXIT-CLEAN, so the conformance
  harness scored it a pass while it was wrong.

  THE STRIDE WAS NEVER WRONG. `a d g` is elements 0, 3 and 6: the loop advanced
  by a full row every time. What failed was the ASSIGNMENT of the row to the
  loop variable. AN_ASSIGN's char-array arm sees a destination that is an
  `array of Char` and a right-hand side whose kind is tyChar -- an array node
  carries its ELEMENT's kind -- reads that as "a Char into a Char array", and
  takes the string desugar, which stores one character and zero-fills.

  So the cause is a MISSING STAMP, not a Char rule. ASTNDRowSubs is the column
  that means "a single leading subscript names a ROW rather than an element",
  and BuildPartialNDIndex sets it beside the index arithmetic in one routine
  precisely so the two cannot separate -- its own comment says a caller that
  set the arithmetic and forgot the stamp would build a sub-array every
  consumer reads as an element. The for-in builder synthesises its own AN_INDEX
  and was the one place where that had happened.

  WHY IT LOOKED LIKE A CHAR BUG AND IS NOT: the INT row was correct throughout,
  because there is no char-array arm for LongInt and the plain store copied the
  destination's size. A defect that only one element type can express still had
  a cause that has nothing to do with that type -- which is why the int rows are
  in this file, above the char ones, as the control that says the stride and the
  row copy were always right.

  fpc 3.2.2 is the oracle for every row.
  bug-p-for-in-over-an-array-of-char-rows-yields-one-character }
program test_for_in_over_an_array_of_char_rows_yields_the_row;

type
  TCharRow = array[1..3] of Char;
  TIntRow  = array[1..3] of LongInt;

var
  { the NAMED-row spelling and the 2-D spelling are the same array and were
    both broken; both are here because nothing in the fix distinguishes them
    and a reader should not have to trust that }
  named: array[1..3] of TCharRow = ('asd', 'sdf', 'ddf');
  flat:  array[1..3, 1..3] of Char;
  ints:  array[1..2] of TIntRow = ((1, 2, 3), (4, 5, 6));
  { a non-zero-based OUTER dimension, so the row index is not also the loop
    counter -- the low bound and the row scale are two different subtractions.
    FULL-WIDTH literals deliberately: a SHORT one ('pq' into a 3-char row) is
    padded with a SPACE by fpc and with #0 by pxx, which is a real divergence
    and a different bug -- putting it in this file would make a for-in fixture
    fail for a reason that has nothing to do with for-in. Recorded separately. }
  lo5:   array[5..6] of TCharRow = ('pqr', 'stu');
  s: TCharRow;
  r: TIntRow;
  i, j: Integer;

begin
  for i := 1 to 3 do
    for j := 1 to 3 do
      flat[i, j] := Chr(Ord('a') + (i - 1) * 3 + (j - 1));

  Writeln('int rows (the control -- always worked):');
  for r in ints do
  begin
    for i := 1 to 3 do Write(' ', r[i]);
    Writeln;
  end;

  Writeln('named char rows:');
  for s in named do Writeln(s);

  Writeln('flat char rows:');
  for s in flat do Writeln(s);

  Writeln('low bound 5:');
  for s in lo5 do Writeln(s);
end.
