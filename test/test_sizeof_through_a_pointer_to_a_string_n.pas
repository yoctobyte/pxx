{ `SizeOf(p^)` where the pointee is a `string[N]`.

  It answered POINTER WIDTH -- 8 for a `^string[10]` where fpc says 11 -- in
  both declaration orders and for every spelling. A `^` anywhere in the operand
  routes SizeOf down its EXPRESSION path, whose fallthrough is
  `TypeSlotSize(szExprTk)`: a kind and no capacity. Every other shape of the
  same question (a type name, a variable, an array, an element, a record field)
  already reached FrozenStrSlotSize.

  ROWS E AND F ARE THE POINT AND ROWS A-D ARE THE MEASUREMENT. A wrong SizeOf
  is not a wrong number on a screen, it is the length argument to FillChar and
  Move: `FillChar(p^, SizeOf(p^), 0)` cleared 8 of 11 bytes, leaving the last
  three characters of the string in place behind a zeroed length. E reads the
  length back through the ORIGINAL variable and F copies the whole slot out, so
  a partial clear or a short copy fails them; neither can be satisfied by
  SizeOf alone being right.

  THE ROW THAT WOULD HAVE BEEN WRONG UNDER THE OBVIOUS FIX IS A. Passing the
  capacity to the sizer and leaving the kind alone -- `SizeOfSlot(szExprTk,
  FrozenStrCapOfDeref(n))` -- answers 24 here, not 11: an ident node for a
  frozen string carries the legacy overloaded tyString, whose length prefix is
  eight bytes against a shortstring's one. That is a loud wrong answer
  replacing a quiet one. The fix reads the kind and the capacity out of the
  same symbol, which is why row G exists: `string[N]` is tyShortString up to
  255 and tyFixedString above it, and only a file carrying BOTH sides of that
  boundary can tell a correct sizer from one that is right by coincidence.

  ORACLE SCOPE. Rows A, B, D, E, F are fpc 3.2.2's own output for the same
  program, byte for byte. Rows C and G have NO oracle and are asserted as ours:
  fpc refuses `PS = ^string[10]` outright (`Parameters or result types cannot
  contain local type definitions`) and caps a shortstring at 255, so neither
  the direct pointer spelling nor the wide kind exists over there.
  bug-p-sizeof-through-a-pointer-to-a-string-n-answers-pointer-width }
program test_sizeof_through_a_pointer_to_a_string_n;

type
  TT = string[10];   PT = ^TT;          { target first, pointer second }
  PE = ^TU;          TU = string[7];    { pointer first, target second }
  PS = ^string[10];                     { direct -- pxx only }
  PW = ^TW;          TW = string[300];  { the wide kind -- pxx only }

var
  v: TT; p: PT;
  u: TU; e: PE;
  d: PS;
  w: TW; q: PW;
  g: TT;
  fails: Integer;

procedure Chk(const what: string; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ' got=', got, ' want=', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  p := @v; e := @u; d := @v; q := @w;

  Chk('A alias, target first',  SizeOf(p^), 11);
  Chk('B alias, pointer first', SizeOf(e^), 8);
  Chk('C direct spelling',      SizeOf(d^), 11);
  Chk('G wide kind',            SizeOf(q^), 312);

  { The controls that were already right, kept so a fix to the deref shape
    cannot be a regression to the shapes that reached the sizer all along. }
  Chk('D named variable',       SizeOf(v),  11);
  Chk('H named wide variable',  SizeOf(w),  312);
  Chk('I type name',            SizeOf(TT), 11);

  { ---- the consequence, not the number ---- }
  v := 'abcdefghij'; g := 'GUARD';
  FillChar(p^, SizeOf(p^), 0);
  Chk('E FillChar cleared the whole slot', Length(v), 0);
  if g <> 'GUARD' then
  begin
    WriteLn('FAIL E FillChar ran past the slot, guard=', g);
    fails := fails + 1;
  end;

  v := 'abcdefghij';
  Move(p^, g, SizeOf(p^));
  if g <> 'abcdefghij' then
  begin
    WriteLn('FAIL F Move copied a short slot, got=', g, ' len=', Length(g));
    fails := fails + 1;
  end;

  WriteLn('fails=', fails);
  WriteLn('SIZEOFDEREFSTRN OK');
end.
