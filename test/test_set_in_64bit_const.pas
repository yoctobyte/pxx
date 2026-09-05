program test_set_in_64bit_const;
{ bug-p-set-membership-item-constant-truncated-to-32-bits: `x in [consts]` is
  lowered to a compare chain (SPECIAL_IN), and every backend read the element
  through an explicit Integer() cast even though ParseSetConst, ASTIVal and
  IRIVal are all Int64. The parser narrowed it first (loVal/hiVal were
  Integer), so BOTH halves had to be widened -- fixing either alone leaves the
  rows below red, which is how the control was run.

  On x86-64 the cast was not even the whole story: `cmp rcx, imm32` (48 81 F9)
  sign-extends a 32-bit immediate, so the encoding cannot hold 2^31 at all.
  The measured boundary was exactly 2147483647 in / 2147483648 out -- the
  immediate's range, not any property of sets.

  Every row is chosen so that a backend which did NOTHING gives the WRONG
  answer -- verified, not assumed: against the pre-fix pin this test reports
  SETIN64 FAILED 5, and the five are A_LOW_MATCH, B_EXACT, C_RANGE,
  H_INT32_MAX_PLUS1 and I_MIXED_WIDTH_SET.

  Run this CROSS. i386/arm32/riscv32 compare only the low word plus a
  "fits in int32" flag, so they still fail A_LOW_MATCH/B_EXACT/C_RANGE --
  bug-a-set-membership-32-bit-backends-truncate-the-set-CONSTANT. }

var
  fails: Integer;
  q: Int64;

procedure Chk(got, want: Boolean; const what: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { Truncating 2^32+1 to 32 bits yields 1, so a narrow compare says TRUE. }
  q := 1;
  Chk(q in [4294967297], False, 'A_LOW_MATCH');

  { The same truncation makes the genuine member miss. }
  q := 4294967297;
  Chk(q in [4294967297], True, 'B_EXACT');

  { Range bounds go through the same cast; truncation gives [0..4]. }
  q := 4294967296;
  Chk(q in [4294967296..4294967300], True, 'C_RANGE');
  q := 5;
  Chk(q in [4294967296..4294967300], False, 'C_RANGE_LOW_MISS');

  { Elements above a byte set but inside int32 -- these already worked, and are
    here so a fix that narrows the domain the other way is caught. }
  q := 300;    Chk(q in [300], True, 'D_300');
  q := 70000;  Chk(q in [70000], True, 'E_70000');
  q := 3;      Chk(q in [1, 3, 5], True, 'F_SMALL_SET');
  q := 4;      Chk(q in [1, 3, 5], False, 'F_SMALL_SET_MISS');

  { The int32 boundary, both sides -- this is where x86-64's imm32 ran out. }
  q := 2147483647;  Chk(q in [2147483647], True, 'G_INT32_MAX');
  q := 2147483648;  Chk(q in [2147483648], True, 'H_INT32_MAX_PLUS1');

  { A set MIXING a wide and a narrow element, so the item loop runs more than
    once and a fix that only handles a single-element set is caught.
    This row was first written as a "truncation gets it right by coincidence"
    row and that was wrong -- measured against the pre-fix pin it FAILS like
    the rest, because x86-64 sign-extends the imm32 and 2^32+1 truncates to 1,
    which the 64-bit test value does not equal either. A genuine coincidence
    row needs the test value to be small too, and that is A_LOW_MATCH above. }
  q := 4294967297;
  Chk(q in [4294967297, 9], True, 'I_MIXED_WIDTH_SET');

  if fails = 0 then WriteLn('SETIN64 OK')
  else WriteLn('SETIN64 FAILED ', fails);
end.
