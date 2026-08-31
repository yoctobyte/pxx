{ SizeOf(<type name>) must agree with SizeOf(<variable of that type>).

  These two answers came from two different tables. The declaration path used
  BuiltinScalarTypeKind; SizeOf used BuiltinTypeNameTk, which kept its own list.
  The split was fixed one name at a time three times -- Real, bare string, then
  Extended -- and the audit that came with the third found EIGHT more names the
  declaration path accepted and SizeOf rejected outright with "SizeOf: unknown
  type or variable": ValReal, TDateTime, Currency, Comp, LongBool, WordBool,
  ByteBool, OleVariant. `var v: Currency` compiled; `SizeOf(Currency)` did not.

  Every line below is therefore BOTH halves: the type-name form and the
  variable form, which must print the same number. A regression re-splitting the
  tables shows up as a differing pair, not as a crash.

  ITS COMPLEMENT IS test/test_sizeof_user_name_shadows_builtin.pas (frank-rust),
  and the two MUST stay separate files -- this is not tidiness, it is a
  correctness constraint. Every name below has to MEAN the builtin for these
  rows to say anything; that file declares user types and variables wearing
  those same names, so the two sets of expectations are mutually exclusive by
  construction. Merging them would silently turn control rows here into
  assertions about the user's declarations: `SizeOf(LongBool)` is 4 here and 1
  there, and BOTH are correct.

  Read together they are the pair that matters. This file pins that the builtin
  table answers; that one pins that a USER declaration BEATS it. ce4d9004c had
  the first and not the second, and shipped a wrong-answer regression -- a
  control drawn only from the population a change is about cannot detect a
  change to that population's edge.

  Widths are pxx's own and several differ from FPC deliberately -- Extended and
  ValReal alias Double on every target (feature-extended-alias-or-reject), and
  Variant/OleVariant use pxx's representation. That is not what this test is
  about: it pins SELF-CONSISTENCY, which is what was broken.
  bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets }
program test_sizeof_builtin_type_names;
{$mode objfpc}
var
  vExt: Extended; vVal: ValReal; vDT: TDateTime; vCur: Currency; vComp: Comp;
  vLB: LongBool; vWB: WordBool; vBB: ByteBool; vOV: OleVariant;
  vReal: Real; vSng: Single; vDbl: Double; vVar: Variant;
  bad: Integer;

procedure Chk(const nm: AnsiString; byName, byVar: Integer);
begin
  if byName <> byVar then
  begin
    Writeln('SPLIT ', nm, ' name=', byName, ' var=', byVar);
    Inc(bad);
  end;
end;

begin
  bad := 0;
  Chk('Extended',   SizeOf(Extended),   SizeOf(vExt));
  Chk('ValReal',    SizeOf(ValReal),    SizeOf(vVal));
  Chk('TDateTime',  SizeOf(TDateTime),  SizeOf(vDT));
  Chk('Currency',   SizeOf(Currency),   SizeOf(vCur));
  Chk('Comp',       SizeOf(Comp),       SizeOf(vComp));
  Chk('LongBool',   SizeOf(LongBool),   SizeOf(vLB));
  Chk('WordBool',   SizeOf(WordBool),   SizeOf(vWB));
  Chk('ByteBool',   SizeOf(ByteBool),   SizeOf(vBB));
  Chk('OleVariant', SizeOf(OleVariant), SizeOf(vOV));
  Chk('Real',       SizeOf(Real),       SizeOf(vReal));
  Chk('Single',     SizeOf(Single),     SizeOf(vSng));
  Chk('Double',     SizeOf(Double),     SizeOf(vDbl));
  Chk('Variant',    SizeOf(Variant),    SizeOf(vVar));
  { the widths themselves, so a silent change to one is visible too }
  Writeln(SizeOf(Extended), ' ', SizeOf(ValReal), ' ', SizeOf(Currency), ' ',
          SizeOf(Comp), ' ', SizeOf(LongBool), ' ', SizeOf(WordBool), ' ',
          SizeOf(ByteBool));
  Writeln('splits ', bad);
end.
