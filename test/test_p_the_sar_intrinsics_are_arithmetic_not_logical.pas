{ SarShortint/SarSmallint/SarLongint/SarInt64 — FPC's System ARITHMETIC
  shift-right intrinsics.

  They are declared in FPC's systemh.inc as `[internproc:fpc_in_sar_x]` and
  `[internproc:fpc_in_sar_x_y]`, so there is no unit anywhere that can supply
  them: a compiler either folds them or cannot compile source that calls them.
  FPC's own compiler calls SarInt64 (cutils.pas:1322, LengthSleb128), which is
  the first failure of `uses constexp` under umbrella-pxx-compiles-fpc-itself.

  WHY THE NEGATIVE ROWS ARE THE TEST AND THE POSITIVE ONES ARE NOT:
  an arithmetic and a logical shift AGREE on every non-negative operand, so a
  suite of positive rows would pass against a fold that used the wrong
  operator. Each negative row below is one where the logical answer is a large
  positive (pxx shifts at native width: -16 shr 2 = 4611686018427387900) and
  the arithmetic answer is small and negative. Those rows are the ones that
  can fail; the positive rows are regression ballast and are labelled so.

  Every expected value was read off fpc 3.3.1 running this same source.        }
program test_p_the_sar_intrinsics_are_arithmetic_not_logical;

var
  fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

var
  b: ShortInt;
  s: SmallInt;
  l: LongInt;
  q: Int64;
begin
  fails := 0;

  { --- the rows that can fail: negative operands, two-argument form --- }
  b := -128; Chk('SarShortint(-128,1)', SarShortint(b, 1), -64);
  b := -16;  Chk('SarShortint(-16,2)',  SarShortint(b, 2), -4);
  s := -16;  Chk('SarSmallint(-16,2)',  SarSmallint(s, 2), -4);
  s := -1;   Chk('SarSmallint(-1,15)',  SarSmallint(s, 15), -1);
  l := -16;  Chk('SarLongint(-16,2)',   SarLongint(l, 2), -4);
  l := -17;  Chk('SarLongint(-17,2)',   SarLongint(l, 2), -5);
  q := -16;  Chk('SarInt64(-16,2)',     SarInt64(q, 2), -4);
  q := -1;   Chk('SarInt64(-1,63)',     SarInt64(q, 63), -1);

  { --- the rows that can fail: negative operands, ONE-argument form.
        FPC's one-arg overload shifts by exactly 1.                     --- }
  b := -128; Chk('SarShortint(-128)',   SarShortint(b), -64);
  s := -16;  Chk('SarSmallint(-16)',    SarSmallint(s), -8);
  l := -16;  Chk('SarLongint(-16)',     SarLongint(l), -8);
  q := -16;  Chk('SarInt64(-16)',       SarInt64(q), -8);
  q := -17;  Chk('SarInt64(-17)',       SarInt64(q), -9);

  { --- regression ballast: a logical fold passes every one of these --- }
  b := 64;   Chk('SarShortint(64,2)',   SarShortint(b, 2), 16);
  s := 1000; Chk('SarSmallint(1000,3)', SarSmallint(s, 3), 125);
  l := 1000; Chk('SarLongint(1000,3)',  SarLongint(l, 3), 125);
  q := 1000; Chk('SarInt64(1000,3)',    SarInt64(q, 3), 125);
  q := 1000; Chk('SarInt64(1000)',      SarInt64(q), 500);

  { --- a shift of an EXPRESSION, not just a variable: the fold must parse a
        full argument expression, and it must not evaluate it twice.    --- }
  q := -20;  Chk('SarInt64(q+4,2)',     SarInt64(q + 4, 2), -4);

  { --- Pascal's own `shr` must stay LOGICAL. This is the positive control
        for the pair staying distinct: if the Sar fold had been wired to the
        logical operator, or `shr` to the arithmetic one, this row moves.  }
  q := -16;
  Chk('q shr 2 stays logical', q shr 2, 4611686018427387900);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('SAR OK');
end.
