program test_low_high_and_length_of_a_partial_subscript_answer_the_remaining_dimension;
{ bug-p-low-and-high-of-a-nested-static-array-row-answer-the-outer-arrays-bounds

  `Low(m[5])`, `High(m[5])` and `Length(m[5])` over
  `array[5..9, 2..3, 7..10] of LongInt` answered 5, -1 and 0 -- at EVERY depth,
  for both spellings -- where fpc 3.2.2 answers 2, 3 and 2.

  TWO DIFFERENT WRONG ANSWERS FROM ONE MISSING CONCEPT, which is why the
  asymmetry between the two chains is not the bug. High's whole-array arms each
  carry `(ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx)`, so a
  subscripted operand fell past them to the runtime Length-1 tail and answered
  -1. Low's equivalents do not carry that guard: they test the SYMBOL the
  operand starts at and never ask whether the operand IS that identifier, so
  they fired on `Low(m[5])` exactly as on `Low(m)` and answered the OUTER lower
  bound, 5. Copying High's guard across would have moved Low from 5 to the
  `else 0` tail -- 0 against fpc's 2 -- so the guard was never the fix.

  WHY THE ANSWER HAD NOWHERE TO COME FROM: pxx FLATTENS nested static
  dimensions, because `array[a] of array[b] of T` has the layout of
  `array[a, b] of T`. So there is no symbol, no type and no node in this
  compiler that represents "one row of m", and the bound cannot come from the
  operand at all. It comes from the BASE's dimension row plus the count of
  subscripts already spelled -- ASTNDRowSubs, which BuildPartialNDIndex has
  been stamping all along, and NodeArrNDInfo, which has held the dimension
  rows all along. Nothing new is recorded; they had never been asked TOGETHER.

  THE THIRD DIMENSION IS NOT DECORATION. NDRowSourceInfo, one function above
  the new reader and over the same data, returns the FLAT PRODUCT over the
  dimensions still unconsumed -- correct for the const-array parameter that
  asks it, and wrong for Length, which wants dim k's span alone. On a 2-D array
  the two numbers are equal. A reader that answered the other question would be
  right on every array anyone had probed and wrong from three dimensions on,
  which is why rows 7..9 exist and why they are a 3-D array.

  `5 -1 0` is a good broken instrument to have had: -1 and 0 are not plausible
  bounds for anything, so nothing collides with the do-nothing answer. Rows
  that expect a lower bound of 0 or a length of 0 would not have this property
  and none are written here.

  Every row is byte-identical to fpc 3.2.2. }

type
  TFlat = array[5..9, 2..3] of LongInt;
  TNest = array[5..9] of array[2..3] of LongInt;
  TDeep = array[5..9, 2..3, 7..10] of LongInt;

var
  fails: Integer;
  acc, j: LongInt;
  f: TFlat;
  n: TNest;
  d: TDeep;
  z: array[0..2, 0..1] of LongInt;

procedure Check(const what: AnsiString; got, want: LongInt);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;

  { 1..3: THE CONTROLS. A whole multi-dim array reports dim 0, and those arms
    were correct before -- they are the ones the new arm must not shadow. }
  Check('1: Low of the whole array', Low(f), 5);
  Check('2: High of the whole array', High(f), 9);
  Check('3: Length of the whole array', Length(f), 5);

  { 4..6: one subscript spelled, so the answer is dim 1. }
  Check('4: Low of a partial subscript', Low(f[5]), 2);
  Check('5: High of a partial subscript', High(f[5]), 3);
  Check('6: Length of a partial subscript', Length(f[5]), 2);

  { 7..9: TWO subscripts on a 3-D array. This is the row pair that separates
    dim k's SPAN from the flat product over dims k..n-1: after one subscript
    the sub-array holds 2*4 = 8 elements and Length is 2, not 8. }
  Check('7: Length after one subscript is dim 1, not the flat product',
        Length(d[5]), 2);
  Check('8: Low after two subscripts', Low(d[5, 2]), 7);
  Check('9: High after two subscripts', High(d[5, 2]), 10);

  { 10..12: the NESTED spelling. `array[5..9] of array[2..3]` is flattened to
    the same thing as `array[5..9, 2..3]`, so it must answer identically -- and
    the ticket was written against this spelling. }
  Check('10: Low, nested spelling', Low(n[5]), 2);
  Check('11: High, nested spelling', High(n[5]), 3);
  Check('12: Length, nested spelling', Length(n[5]), 2);

  { 13: the bracket-chain spelling of the same subscript. `d[5][2]` and
    `d[5, 2]` are one AST in this compiler; asserting both is what says so. }
  Check('13: Low, bracket-chain spelling', Low(d[5][2]), 7);

  { 14, 15: a ZERO-BASED array, and row 14 is the one row here that CANNOT
    FAIL. Measured with the arm reverted and the compiler rebuilt: twelve of
    the sixteen rows fail, and the four survivors are the three whole-array
    controls plus this one -- because 0 is also what the broken path answered.
    It is kept, labelled, because a reader comparing this file against the
    ticket's `5 -1 0` needs to see that the zero-based case was checked; row 15
    beside it is what actually discriminates, since a length of 2 does not
    collide with the tail's 0. }
  Check('14: Low of a zero-based row', Low(z[0]), 0);
  Check('15: Length of a zero-based row', Length(z[0]), 2);

  { 16: the bounds are usable as a LOOP range, which is the reason the
    intrinsics exist. Answering -1 for High made `for j := Low(r) to High(r)`
    not run at all, and a row that only compares numbers would not have caught
    the shape of that failure. }
  f[5, 2] := 11; f[5, 3] := 22;
  acc := 0;
  for j := Low(f[5]) to High(f[5]) do acc := acc + f[5, j];
  Check('16: the bounds drive a loop that runs', acc, 33);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('PARTIALSUBBOUNDS OK');
end.
