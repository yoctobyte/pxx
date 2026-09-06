{ `d := s` with `d: array of LongInt` and `s: array[0..2] of LongInt` stored the
  STATIC array's ADDRESS into the dynamic array's handle slot. Length then read
  the words in front of `s` as a managed-block header: measured Length(d) =
  4310328 and a SEGFAULT walking it, where fpc prints `len=3: 2 4 6`. Silent
  garbage, then a crash, from four lines of ordinary Pascal.

  The kind check could not see it: an array symbol's TypeKind is its ELEMENT's
  kind, so both sides are tyInteger and AssignKindsIncompatible sees a MATCHING
  pair -- it does not merely stay silent, it certifies the assignment.

  Now COPIED, through the array constructor that `d := [1, 2, 3]` already uses,
  so the elements go through the normal element-assign path and carry coercion
  and managed-element ARC with them.

  THE AXES, and the count of rows is not what makes this complete:
    - element KIND: LongInt (plain), Char (one byte), AnsiString (MANAGED -- a
      byte copy would duplicate the handles without retaining them), and a
      RECORD (bytes wider than a slot).
    - LOW BOUND: `array[1..3]` as well as `array[0..2]`. Three elements either
      way, and only the second is what a zero-assuming index literal would
      produce. fpc REFUSES a non-zero low bound here ("Incompatible types: got
      Array[1..3] Of Char"); we accept it and answer what the source means, and
      us accepting what fpc rejects is not a defect.
    - INDEPENDENCE: the destination must be a COPY. `s[0] := 99` after the
      assignment must not move `d[0]` -- that is the one assertion the original
      bug could never have passed, since the handle held s's own address.
    - EMPTY-ish: a one-element source, so the loop bound is exercised at 1.
    - a FIXED-ROW destination (`d: array of TRow`), which is the shape that was
      refused for a day: `array[0..1] of TRow` is FLATTENED to a 2-D array, so
      the source's ArrLen is the SIX elements and not the two rows and a plain
      `s[i]` would index one LongInt. It needs BuildPartialNDRowIndex, which
      scales the leading subscript AND stamps ASTNDRowSubs. Its own
      independence row is separate because a row copy has more ways to alias
      than a scalar one.

  fpc 3.2.2 is the oracle for every row whose low bound is 0; the two `1..N`
  rows it refuses outright and their values are ours.
  bug-a-a-static-array-assigned-to-a-dynamic-array-stores-its-address }
program test_a_static_array_is_copied_into_a_dynamic_array;

type
  TR = record a, b: LongInt; end;
  TRow = array[0..2] of LongInt;

var
  d: array of LongInt;
  s: array[0..2] of LongInt;
  s1: array[1..3] of LongInt;
  c: array of Char;
  t: array[1..3] of Char;
  b: array of AnsiString;
  a: array[0..1] of AnsiString;
  dr: array of TR;
  sr: array[0..1] of TR;
  one: array of LongInt;
  s0: array[0..0] of LongInt;
  dw: array of TRow;
  sw: array[0..1] of TRow;
  i, j: Integer;

begin
  s[0] := 2; s[1] := 4; s[2] := 6;
  d := s;
  Write('int   len=', Length(d), ':');
  for i := 0 to Length(d) - 1 do Write(' ', d[i]);
  Writeln;

  { the copy is a COPY -- this is the row the address bug could not pass }
  s[0] := 99;
  Writeln('independent: d[0]=', d[0], ' s[0]=', s[0]);

  s1[1] := 7; s1[2] := 8; s1[3] := 9;
  d := s1;
  Write('lo1   len=', Length(d), ':');
  for i := 0 to Length(d) - 1 do Write(' ', d[i]);
  Writeln;

  t[1] := 'x'; t[2] := 'y'; t[3] := 'z';
  c := t;
  Write('char  len=', Length(c), ':');
  for i := 0 to Length(c) - 1 do Write(' ', c[i]);
  Writeln;

  a[0] := 'foo'; a[1] := 'bar';
  b := a;
  Write('str   len=', Length(b), ':');
  for i := 0 to Length(b) - 1 do Write(' ', b[i]);
  Writeln;

  sr[0].a := 1; sr[0].b := 2; sr[1].a := 3; sr[1].b := 4;
  dr := sr;
  Write('rec   len=', Length(dr), ':');
  for i := 0 to Length(dr) - 1 do Write(' ', dr[i].a, '/', dr[i].b);
  Writeln;

  s0[0] := 42;
  one := s0;
  Write('one   len=', Length(one), ':');
  for i := 0 to Length(one) - 1 do Write(' ', one[i]);
  Writeln;

  sw[0][0] := 1; sw[0][1] := 2; sw[0][2] := 3;
  sw[1][0] := 4; sw[1][1] := 5; sw[1][2] := 6;
  dw := sw;
  Write('row   len=', Length(dw), ':');
  for i := 0 to Length(dw) - 1 do
  begin
    Write(' [');
    for j := 0 to 2 do Write(' ', dw[i][j]);
    Write(' ]');
  end;
  Writeln;

  { a row copy has more ways to alias than a scalar one, so it gets its own }
  sw[0][0] := 99;
  Writeln('row independent: dw[0][0]=', dw[0][0], ' sw[0][0]=', sw[0][0]);
end.
