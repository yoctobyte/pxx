program test_a_nil_argument_prefers_a_named_dynamic_array_over_an_open_array;
{ bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature

  With `Test(const a: array of LongInt)` and `Test(const a: TLA)` both in
  scope, `Test(nil)` bound whichever was DECLARED FIRST. fpc 3.2.2 binds the
  named dynamic array in BOTH orders:

      open-first    fpc: dyn    pxx: open
      dyn-first     fpc: dyn    pxx: dyn

  A typed argument already chose correctly -- `t: TLA; Test(t)` binds dyn in
  both orders -- so the finer channel worked and only the literal `nil` fell
  through to declaration order. That asymmetry is row 3's job.

  WHY IT IS A PHASE AND NOT AN EXACT MATCH, which is the part a single probe
  gets wrong. `Params[j].TypeKind` on an array parameter is its ELEMENT's kind,
  so both candidates compare tyInteger against nil's tyPointer and NEITHER is
  exact -- one-field-two-meanings surfacing as an overload bug. The obvious fix
  is to make nil-at-a-dyn-array exact; measured, that would have been wrong:
  `P(a: Pointer)` against `P(const a: TLA)` given nil binds the POINTER under
  fpc in both orders, and pxx already agreed, so an exact-phase arm would have
  flipped the dyn-first program and traded one declaration-order bug for
  another. Rows 4 and 5 are that measurement kept.

  AND IT IS A PREFERENCE, NOT A COMPATIBILITY RULE. fpc REFUSES nil for an
  open-array parameter outright -- "Incompatible type for arg no. 1: Got
  Pointer, expected Array Of LongInt", which fpc spells with a brace-wrapped
  Open in front of Array and which therefore cannot be quoted verbatim inside a
  Pascal comment -- where pxx accepts it. Us
  accepting what fpc rejects is not a defect, so that stays: a LONE open-array
  candidate still binds. That row cannot live in this file, because fpc will
  not compile it; it is asserted in the Makefile as a separate program whose
  output is checked directly, and named here so a reader does not think it was
  forgotten.

  Every row below is byte-identical to fpc 3.2.2. }

type
  TLA = array of LongInt;

var
  fails: Integer;
  got: AnsiString;
  t: TLA;

procedure Check(const what, g, w: AnsiString);
begin
  if g <> w then
  begin
    WriteLn('FAIL ', what, ': got "', g, '" want "', w, '"');
    fails := fails + 1;
  end;
end;

{ OPEN declared FIRST -- the order that was wrong. }
procedure OpenFirst(const a: array of LongInt); overload;
begin got := 'open'; end;
procedure OpenFirst(const a: TLA); overload;
begin got := 'dyn'; end;

{ ...and DYN declared first, the order that happened to be right. Both are
  here because the defect IS the order dependence, and a file with one order
  cannot see it. }
procedure DynFirst(const a: TLA); overload;
begin got := 'dyn'; end;
procedure DynFirst(const a: array of LongInt); overload;
begin got := 'open'; end;

{ A POINTER parameter must keep beating the dynamic array, in both orders.
  This is the control that stops the fix from being written in the exact
  phase. }
procedure PtrFirst(a: Pointer); overload;
begin got := 'ptr'; end;
procedure PtrFirst(const a: TLA); overload;
begin got := 'dyn'; end;

procedure DynBeforePtr(const a: TLA); overload;
begin got := 'dyn'; end;
procedure DynBeforePtr(a: Pointer); overload;
begin got := 'ptr'; end;

{ A SECOND argument that is merely compatible, not exact -- a ShortString
  literal against an AnsiString parameter. The phase must not require an
  all-exact call, which is the trap Phase 1c1 records for the Variant case:
  the defect there stayed hidden while every other argument matched exactly. }
procedure TwoArgs(const a: array of LongInt; const s: AnsiString); overload;
begin got := 'open'; end;
procedure TwoArgs(const a: TLA; const s: AnsiString); overload;
begin got := 'dyn'; end;

{ A nil at a NON-array parameter beside one at an array parameter. The phase
  keys on the nil that lands on an array; the other must not disturb it. }
procedure Mixed(p: Pointer; const a: array of LongInt); overload;
begin got := 'open'; end;
procedure Mixed(p: Pointer; const a: TLA); overload;
begin got := 'dyn'; end;

begin
  fails := 0;

  { 1: THE ROW THIS FILE EXISTS FOR. }
  got := ''; OpenFirst(nil);
  Check('1: nil with the open overload declared first', got, 'dyn');

  { 2: the same call with the declarations swapped. Passing this one alone
    proves nothing -- it passed before the fix. }
  got := ''; DynFirst(nil);
  Check('2: nil with the dyn overload declared first', got, 'dyn');

  { 3: a TYPED argument, which already chose correctly. The boundary: it says
    the finer channel works and only the literal fell through. }
  t := nil;
  got := ''; OpenFirst(t);
  Check('3: a typed dyn-array argument, open declared first', got, 'dyn');
  got := ''; DynFirst(t);
  Check('4: a typed dyn-array argument, dyn declared first', got, 'dyn');

  { 5, 6: A POINTER PARAMETER STILL WINS, both orders. If these two ever
    disagree with each other, the fix has moved into the exact phase. }
  got := ''; PtrFirst(nil);
  Check('5: Pointer beats the dyn array, Pointer first', got, 'ptr');
  got := ''; DynBeforePtr(nil);
  Check('6: Pointer beats the dyn array, dyn first', got, 'ptr');

  { 7: a merely-compatible second argument must not disqualify the phase. }
  got := ''; TwoArgs(nil, 'x');
  Check('7: with a merely-compatible second argument', got, 'dyn');

  { 8: a nil at a non-array parameter beside the one that matters. }
  got := ''; Mixed(nil, nil);
  Check('8: a second nil at a non-array parameter', got, 'dyn');

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('NILARRPREF OK');
end.
