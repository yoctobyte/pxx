program test_sizeof_stringn_matches_storage;
{ SizeOf must agree with the compiler's OWN storage for a `string[N]`.

  THE THIRD IN A FAMILY, and the arm the second one left behind.
  test_sizeof_real_matches_storage.pas and test_sizeof_string_matches_storage.pas
  assert this identity for a real and for a managed `string`; that second fix
  unified the two tables answering "what is a bare `string`" and stopped at the
  bare spelling. `string[N]` goes through the same SizeOf arms and was still
  answering the pointer width. Fixed one arm of a double case, and the sibling
  stayed broken -- devdocs/dev/normalise-dont-special-case.md, which is why this
  test is deliberately the same SHAPE as its sibling rather than a fresh idea.

  It did not: SizeOf answered the pointer width (8) for every shape of a
  `string[10]`, while the layout engine gave that same type cap+8 = 18 -- so
  `SizeOf(array[0..2] of string[10])` was 24 while its elements sat 18 apart,
  and the array claimed less storage than its own elements occupied.

  WHY THE ASSERTIONS ARE SELF-CONSISTENCY AND NOT FPC'S NUMBERS. FPC answers 11
  where we answer 18, because `string[N]` maps onto tyFixedString (an 8-byte
  length word) here and onto tyShortString (one length byte) there. That is an
  open REPRESENTATION question and this test must not prejudge it: pinning 18
  would make the test fail the day that question is settled, for a change that
  is not a regression. Comparing SizeOf against the MEASURED STRIDE asserts the
  property that must hold under either answer -- the two numbers agree.

  WHY THERE ARE SIZE ROWS AT ALL, AND WHY THEY COME FIRST. The FillChar and
  Move rows below are the ones that show a wrong VALUE, but on their own they
  would have certified the bug as correct for years: every element that fits
  within the first SizeOf(a) bytes was always copied and cleared correctly.
  Only a row that reads the size itself can observe this defect.
  bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more }
type
  S10 = string[10];
  A3  = array[0..2] of S10;
  TRc = record f: S10; g: Byte; end;
var
  sv: S10;
  inl: string[10];
  av, bv: A3;
  rv: TRc;
  pl: string;
  stride, i, gbad: LongInt;
  guard: array[0..31] of LongInt;
  p0, p1: ^Byte;
begin
  p0 := @av[0]; p1 := @av[1];
  stride := LongInt(p1) - LongInt(p0);

  { The size rows. Each is SizeOf against the storage actually in use. }
  WriteLn('alias      ', Ord(SizeOf(S10)  = stride));
  WriteLn('var        ', Ord(SizeOf(sv)   = stride));
  WriteLn('inline     ', Ord(SizeOf(inl)  = stride));
  WriteLn('arrtype    ', Ord(SizeOf(A3)   = stride * 3));
  WriteLn('arrvar     ', Ord(SizeOf(av)   = stride * 3));
  WriteLn('element    ', Ord(SizeOf(av[0])= stride));
  WriteLn('field      ', Ord(SizeOf(rv.f) = stride));

  { EVERY ROW ABOVE IS AN INTERNAL-CONSISTENCY INVARIANT, and that is a real
    limit rather than a style: `stride` is the layout engine's own answer, so
    asserting SizeOf against it proves the two AGREE and can never notice they
    are wrong TOGETHER. That is not hypothetical -- it is exactly the next bug
    found in this family, where a record field's array strode 264 with SizeOf
    agreeing at 36 only because SizeOf was reading a different path. The rows
    below are the missing dimension: bounds that come from the DECLARATION, and
    containment, neither of which the layout engine gets a vote on.

    An absolute bracket on the slot. A `string[10]` must hold a length prefix
    and ten chars, so it cannot be smaller than 11; and the prefix is a length
    word, so it cannot be larger than 8+10. Both ends are the DECLARED capacity,
    not a measurement, and the bracket is deliberately wide enough to survive
    the pending change of the prefix from eight bytes to one (18 -> 11, still
    inside it) while rejecting the 263/264 defaults this family keeps
    substituting when a capacity goes missing. }
  WriteLn('bracket    ', Ord((stride >= 11) and (stride <= 18)));

  { CONTAINMENT: the last element must END INSIDE the array. This is the row a
    self-consistent pair cannot satisfy by being wrong together -- an
    over-strided array reports a matching SizeOf and still runs off its own
    end. }
  p0 := @av[0]; p1 := @av[2];
  WriteLn('contained  ', Ord((LongInt(p1) - LongInt(p0)) + stride <= SizeOf(av)));

  { A record containing one, bounded on BOTH sides. The old row was
    `>= stride + 1`, which cannot fail upward: a record bloated by an
    over-strided field satisfies it. }
  WriteLn('record     ', Ord((SizeOf(TRc) >= stride + 1) and
                             (SizeOf(TRc) <= stride + 16)));

  { The BOUNDARY, and the one row that is deliberately NOT portable to FPC. A
    plain managed string is a handle here, so its SizeOf is honestly the pointer
    width and must NOT move with the rest. FPC answers 0 for this row and is
    equally right about ITSELF: its plain `string` is a string[255], so 256.
    Two representations, each reported faithfully. The row exists to catch a
    fix that over-reaches from `string[N]` into the managed model. }
  WriteLn('plainstr   ', Ord(SizeOf(pl) = SizeOf(Pointer)));

  { The value rows: the idiom that made the wrong size observable. The guard
    catches the OTHER failure mode in this family -- writes that land outside
    the aggregate entirely, which every value assertion passes because the
    write and the read share the same wrong stride and agree with each other
    out there. }
  for i := 0 to 31 do guard[i] := 12345;
  av[0] := 'aaaaaaaaaa'; av[1] := 'bbbbbbbbbb'; av[2] := 'cccccccccc';
  gbad := 0;
  for i := 0 to 31 do if guard[i] <> 12345 then gbad := gbad + 1;
  WriteLn('guard      ', Ord(gbad = 0));
  FillChar(av, SizeOf(av), 0);
  Write('fillchar   ');
  for i := 0 to 2 do Write(Ord(Length(av[i]) = 0));
  WriteLn;

  av[0] := 'aaaaaaaaaa'; av[1] := 'bbbbbbbbbb'; av[2] := 'cccccccccc';
  FillChar(bv, SizeOf(bv), 0);
  Move(av, bv, SizeOf(av));
  Write('move       ');
  for i := 0 to 2 do Write(Ord(bv[i] = av[i]));
  WriteLn;

  { Capacity still truncates at N, and the declared N is still a separate fact
    from the slot size -- the same split the subrange fix had to preserve. }
  sv := 'abcdefghijklmno';
  WriteLn('truncate   ', Ord(Length(sv) = 10), Ord(sv = 'abcdefghij'));
end.
