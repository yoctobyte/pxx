program test_shortstring_mixed_widths;
{ TWO FROZEN STRING WIDTHS IN ONE PROGRAM, ASSIGNING BOTH DIRECTIONS.

  A copy between two frozen strings stopped being a copy the moment a second
  prefix width existed: it is a CONVERSION, and the two sides can disagree.
  This test exists because the phase-2 test (test_shortstring_byte_prefix)
  holds exactly one string and therefore cannot see a width MISMATCH at all --
  it proved the narrow layout is right and said nothing about crossing between
  widths.

  IT FOUND TWO REAL BUGS ON THE BACKEND THAT HAD ALREADY BEEN DECLARED
  COMPLETE, and both were in the narrow -> wide direction only:

    * frozen -> frozen (`b := s`, b a frozen `string`, s a `string[10]`) read
      the source length off `IRTk[valueNode]`, which the IR tags tyString
      GENERICALLY for every frozen string. So it read 8 bytes of [len][chars]
      as a length, clamped it to the destination cap, and printed 255 blanks.
    * frozen -> managed (`b := s` with b an AnsiString) did the same in
      EmitAnsiStrFromInlineString, where the billions-long length reached the
      allocator: `out of memory (heap arena mmap failed)`.

  THE WIDE -> NARROW DIRECTION WAS CORRECT THROUGHOUT, and that is the point:
  tyString is also the fallback both readers use when they cannot tell, so the
  bug was invisible in precisely the direction a single-width test exercises.
  A guard that only ever narrows cannot fail.

  THE FOUR-MODE MATRIX IS THE ASSERTION, not a thoroughness gesture. There are
  two independent build axes now -- PXX_MANAGED_STRING chooses what bare
  `string` is, PXX_SHORTSTRING chooses what `string[N]` is -- and the mode that
  breaks is the one where the widths are FURTHEST apart. Every row below is
  FPC 3.2.2's own answer, and all four modes must produce it: the two default
  modes prove nothing moved, the two shortstring modes prove the conversion.

  feature-p-implement-the-real-tyshortstring-byte-prefix-layout }
var
  b: string;        { managed, or frozen tyString under -uPXX_MANAGED_STRING }
  s: string[10];    { tyFixedString, or tyShortString under -dPXX_SHORTSTRING }
  i: Integer;
begin
  { WIDE -> NARROW. Correct before the fix; kept as the row that must not move. }
  b := 'hello';
  s := b;
  WriteLn('w2n      ', Length(s), ' <', s, '>');

  { NARROW -> WIDE. This is the row that printed 255 blanks, and the row that
    crashed the allocator in managed mode. }
  s := 'world';
  b := s;
  WriteLn('n2w      ', Length(b), ' <', b, '>');

  { Truncation must happen at the DESTINATION's capacity, then survive the
    widening -- so the second row proves the first row's length byte was
    written, not merely that the chars were copied. }
  s := 'abcdefghijKLMNOP';
  WriteLn('trunc    ', Length(s), ' <', s, '>');
  b := s;
  WriteLn('trunc2w  ', Length(b), ' <', b, '>');

  { The empty string, both directions: the one length a wrong-width read can
    still get right by accident, which is why it is asserted separately rather
    than trusted. }
  s := '';
  WriteLn('empty    ', Length(s), ' <', s, '>');
  b := '';
  s := b;
  WriteLn('emptyw2n ', Length(s));

  { Indexing after a cross-width assignment: s[i] is where a prefix width and a
    char OFFSET disagree, and the two are decided by the same number. }
  s := 'xy';
  Write('chars    ');
  for i := 1 to Length(s) do Write(Ord(s[i]), ' ');
  WriteLn;
end.
