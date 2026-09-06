program test_high_low_of_a_sized_boolean;
{ bug-p-thirteen-builtin-type-names-answer-at-some-doors-and-are-refused-at-others

  High/Low of ByteBool, WordBool, LongBool and QWordBool. All eight answered
  `undefined variable` before this: the name reached the High/Low doors, missed
  OrdinalNameToTk's table, missed the alias arm and fell through to the
  variable path. Every OTHER door already answered for these names --
  declaration, SizeOf, cast, parameter -- so it was one door of six, which is
  what the ticket's title is about.

  THERE IS NO .expected FROM FPC FOR THIS FILE, AND THAT IS THE FINDING.
  Measured against fpc 3.2.2 on 2026-09-06: `Int64(High(ByteBool))` is
  9223372036854775807 and `Int64(Low(ByteBool))` is -9223372036854775808 -- the
  Int64 extremes, THE SAME PAIR FOR ALL FOUR WIDTHS, for a type whose only
  values fpc materialises are 0 and all-bits-set. fpc's own assembler refuses
  the value fpc's front end produced: `b := Low(ByteBool)` for `b: ByteBool` is
  "Asm: byte value exceeds bounds -9223372036854775808", so the assignment rows
  below CANNOT COMPILE under fpc at all -- while `SizeOf(High(ByteBool))`
  answers 1 there, i.e. the expression has the type and the value does not fit
  in it. fpc answers 1/0 for plain Boolean; the sized ones are the ones with no
  range recorded, not a considered choice.

  Ord() HIDES THIS, and that is why it is written out here. `Ord(High(ByteBool))`
  prints -1 under fpc and `Ord(Low(ByteBool))` prints 0 -- the Int64 extremes
  truncated to the type's width -- which are exactly the two values we return.
  A probe reading fpc through Ord reports agreement with us and cannot fail.
  The row that survives truncation is `WriteLn(Low(ByteBool))` printing TRUE in
  fpc while its own Ord is 0.

  So these values are OURS and CHOSEN, per CLAUDE.md's "ON PAR WITH THE
  LANGUAGE, NOT WITH FPC": High is True, Low is False, the bounds of the type
  the caller named. The assignment rows are the point -- a bound you cannot
  store in a variable of its own type is not a bound.

  The last four rows are the CONTROLS: plain Boolean, Byte and ShortInt must
  not have moved, because the new arm sits in the slot the ordinal table
  occupies and a bug there would be silent. }

type TAB = ByteBool;   { the ALIAS spelling, which is a different arm }
     TAW = WordBool;
     TAL = LongBool;
     TAQ = QWordBool;

const CH = High(ByteBool);
      CL = Low(ByteBool);
      CAH = High(TAB);

var b: ByteBool; w: WordBool; l: LongBool; q: QWordBool;
    fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got "', got, '" want "', want, '"');
    fails := fails + 1;
  end;
end;

var s: AnsiString;
begin
  fails := 0;

  { 1-8: the eight doors that were refused. }
  Chk('High(ByteBool)',  Ord(High(ByteBool)),  -1);
  Chk('Low(ByteBool)',   Ord(Low(ByteBool)),    0);
  Chk('High(WordBool)',  Ord(High(WordBool)),  -1);
  Chk('Low(WordBool)',   Ord(Low(WordBool)),    0);
  Chk('High(LongBool)',  Ord(High(LongBool)),  -1);
  Chk('Low(LongBool)',   Ord(Low(LongBool)),    0);
  Chk('High(QWordBool)', Ord(High(QWordBool)), -1);
  Chk('Low(QWordBool)',  Ord(Low(QWordBool)),   0);

  { 9-12: the bound carries the type's WIDTH, not a boolean's. This is the
    half fpc gets right and the reason the node is stamped with the storage
    kind rather than tyBoolean. }
  Chk('SizeOf(High(ByteBool))',  SizeOf(High(ByteBool)),  1);
  Chk('SizeOf(High(WordBool))',  SizeOf(High(WordBool)),  2);
  Chk('SizeOf(High(LongBool))',  SizeOf(High(LongBool)),  4);
  Chk('SizeOf(High(QWordBool))', SizeOf(High(QWordBool)), 8);

  { 13-16: the bound carries the type's MEANING -- it renders as TRUE/FALSE.
    Ord alone cannot see this: -1 and 0 are ordinals either way. }
  Str(High(ByteBool), s);  ChkS('Str High(ByteBool)', s, 'TRUE');
  Str(Low(ByteBool), s);   ChkS('Str Low(ByteBool)', s, 'FALSE');
  Str(High(QWordBool), s); ChkS('Str High(QWordBool)', s, 'TRUE');
  Str(Low(LongBool), s);   ChkS('Str Low(LongBool)', s, 'FALSE');

  { 17-21: A BOUND YOU CANNOT STORE IN ITS OWN TYPE IS NOT A BOUND. These are
    the rows fpc cannot compile. }
  b := High(ByteBool);  Chk('b := High(ByteBool)', Ord(b), -1);
  b := Low(ByteBool);   Chk('b := Low(ByteBool)',  Ord(b),  0);
  w := High(WordBool);  Chk('w := High(WordBool)', Ord(w), -1);
  l := Low(LongBool);   Chk('l := Low(LongBool)',  Ord(l),  0);
  q := High(QWordBool); Chk('q := High(QWordBool)', Ord(q), -1);

  { 22-23: the CONST door, which is a second resolver and not the same code. }
  Chk('const High(ByteBool)', Ord(CH), -1);
  Chk('const Low(ByteBool)',  Ord(CL),  0);
  Str(CH, s); ChkS('Str of the const', s, 'TRUE');

  { 24-31: THE ALIAS SPELLING, which is a SECOND arm and was wrong in two
    different ways in two months. It first answered 255 / 65535 / 2147483647
    from the C-ABI kind -- a silent wrong bound beside the direct spelling's
    loud refusal, which is the worse of the two and what the ticket is named
    for. Once the sized booleans got an identity it became a refusal instead:
    an alias carries its sem in the same slot an ENUM alias uses, so the
    boolean sem was read as an enum id and FindEnumType missed it. Both
    spellings must give the same answer or this test is measuring one door. }
  Chk('High(TAB)', Ord(High(TAB)), -1);
  Chk('Low(TAB)',  Ord(Low(TAB)),   0);
  Chk('High(TAW)', Ord(High(TAW)), -1);
  Chk('Low(TAW)',  Ord(Low(TAW)),   0);
  Chk('High(TAL)', Ord(High(TAL)), -1);
  Chk('Low(TAL)',  Ord(Low(TAL)),   0);
  Chk('High(TAQ)', Ord(High(TAQ)), -1);
  Chk('Low(TAQ)',  Ord(Low(TAQ)),   0);
  Str(High(TAL), s); ChkS('Str High(TAL)', s, 'TRUE');
  Chk('SizeOf(High(TAL))', SizeOf(High(TAL)), 4);
  Chk('const High(TAB)', Ord(CAH), -1);

  { 32-37: THE CONTROLS. The new arm sits where the ordinal table is read; if
    it shadowed a name it must not, these are what says so. }
  Chk('High(Boolean)',  Ord(High(Boolean)), 1);
  Chk('Low(Boolean)',   Ord(Low(Boolean)),  0);
  Chk('High(Byte)',     High(Byte),       255);
  Chk('High(LongInt)',  High(LongInt), 2147483647);
  Chk('High(ShortInt)', High(ShortInt),   127);
  Chk('Low(ShortInt)',  Low(ShortInt),   -128);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('SIZEDBOOLBOUNDS OK');
end.
