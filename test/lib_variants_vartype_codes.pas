{ VarType speaks FPC's varXxx codes, and the varXxx constants exist.

  Every number here was MEASURED from fpc 3.2.2 by printing the constants and
  running the same program, not transcribed from documentation. That matters
  because the set is irregular — varBoolean jumps to 11, the sized integers
  start at 16, and the string codes are up at 256 — so a guessed constant would
  look plausible and be wrong.

  11 of the 12 rows below are byte-for-byte FPC's answer. The ONE deliberate
  divergence is `v := 1`: FPC narrows an integer LITERAL to the smallest type
  that holds it and reports varShortInt (16), while pxx does not narrow and has
  one integer tag, so it reports varInteger (3). The case real code writes —
  `v := someInteger` — agrees with FPC exactly, and that row is asserted right
  next to it so the divergence cannot be mistaken for a general one.

  The one-character row is the point of the fold. Both text tags map onto
  varString, so `VarType(v) = varString` is true for 'x' as well as 'xy'. FPC
  has no char variant at all (`v := c` with c: Char reports 256 there too), so
  this is parity rather than a compromise — and it removes the whole class of
  bug where a caller had to know that 'x' and 'xy' were tagged differently.

  The predicates are asserted to AGREE with VarType on every row. That is the
  actual regression risk of this change: VarType now returns FPC's numbering
  while the predicates read the private tag, so a missed call site would show up
  as a predicate disagreeing with the code its own unit reports. }
program lib_variants_vartype_codes;

uses variants, sysutils;

var
  failures: Integer;

procedure Fail(const what, got, want: AnsiString);
begin
  Inc(failures);
  WriteLn('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure CheckI(const what: AnsiString; got, want: Integer);
begin
  if got <> want then Fail(what, IntToStr(got), IntToStr(want));
end;

procedure CheckB(const what: AnsiString; got, want: Boolean);
var g, w: AnsiString;
begin
  if got = want then Exit;
  if got then g := 'True' else g := 'False';
  if want then w := 'True' else w := 'False';
  Fail(what, g, w);
end;

var
  v: Variant;
  c: Char;
  s: AnsiString;
  i: Integer;
  i64: Int64;
  d: Double;
  b: Boolean;

begin
  failures := 0;

  { The constants themselves — fpc 3.2.2's values. }
  CheckI('varEmpty', varEmpty, 0);
  CheckI('varNull', varNull, 1);
  CheckI('varSmallint', varSmallint, 2);
  CheckI('varInteger', varInteger, 3);
  CheckI('varSingle', varSingle, 4);
  CheckI('varDouble', varDouble, 5);
  CheckI('varCurrency', varCurrency, 6);
  CheckI('varDate', varDate, 7);
  CheckI('varOleStr', varOleStr, 8);
  CheckI('varDispatch', varDispatch, 9);
  CheckI('varError', varError, 10);
  CheckI('varBoolean', varBoolean, 11);
  CheckI('varVariant', varVariant, 12);
  CheckI('varUnknown', varUnknown, 13);
  CheckI('varShortInt', varShortInt, 16);
  CheckI('varByte', varByte, 17);
  CheckI('varWord', varWord, 18);
  CheckI('varLongWord', varLongWord, 19);
  CheckI('varInt64', varInt64, 20);
  CheckI('varQWord', varQWord, 21);
  CheckI('varString', varString, 256);
  CheckI('varUString', varUString, 258);
  CheckI('varTypeMask', varTypeMask, 4095);
  CheckI('varArray', varArray, 8192);
  CheckI('varByRef', varByRef, 16384);

  { VarType per kind. Comment marks each row FPC-identical or divergent. }
  i := 1; v := i;
  CheckI('VarType(Integer var)', VarType(v), varInteger);          { = FPC 3 }
  CheckB('  and VarIsNumeric', VarIsNumeric(v), True);

  v := 1;
  CheckI('VarType(integer literal)', VarType(v), varInteger);      { FPC: 16 }
  CheckB('  and VarIsNumeric', VarIsNumeric(v), True);

  i64 := 1; v := i64;
  CheckI('VarType(Int64)', VarType(v), varInt64);                  { = FPC 20 }
  CheckB('  and VarIsNumeric', VarIsNumeric(v), True);

  d := 1.5; v := d;
  CheckI('VarType(Double)', VarType(v), varDouble);                { = FPC 5 }
  CheckB('  and VarIsNumeric', VarIsNumeric(v), True);

  v := 1.5;
  CheckI('VarType(float literal)', VarType(v), varDouble);         { = FPC 5 }

  b := True; v := b;
  CheckI('VarType(Boolean)', VarType(v), varBoolean);              { = FPC 11 }
  CheckB('  and not VarIsNumeric', VarIsNumeric(v), False);

  v := True;
  CheckI('VarType(True literal)', VarType(v), varBoolean);         { = FPC 11 }

  s := 'xy'; v := s;
  CheckI('VarType(AnsiString)', VarType(v), varString);            { = FPC 256 }
  CheckB('  and VarIsStr', VarIsStr(v), True);

  v := 'xy';
  CheckI('VarType(2-char literal)', VarType(v), varString);        { = FPC 256 }
  CheckB('  and VarIsStr', VarIsStr(v), True);

  { The fold. Internally this is VT_CHAR, not VT_STRING — the whole point is
    that a caller cannot tell, exactly as on FPC. }
  v := 'x';
  CheckI('VarType(1-char literal)', VarType(v), varString);        { = FPC 256 }
  CheckB('  and VarIsStr', VarIsStr(v), True);

  c := 'x'; v := c;
  CheckI('VarType(Char var)', VarType(v), varString);              { = FPC 256 }
  CheckB('  and VarIsStr', VarIsStr(v), True);

  v := Unassigned;
  CheckI('VarType(Unassigned)', VarType(v), varEmpty);             { = FPC 0 }
  CheckB('  and VarIsEmpty', VarIsEmpty(v), True);
  CheckB('  and VarIsNull', VarIsNull(v), True);
  CheckB('  and VarIsClear', VarIsClear(v), True);
  CheckB('  and not VarIsStr', VarIsStr(v), False);
  CheckB('  and not VarIsNumeric', VarIsNumeric(v), False);

  { A non-empty variant is not clear. Guards the VarIsClear call site, which
    reads the private tag and would silently invert if it had been missed. }
  v := 'xy';
  CheckB('VarIsClear(non-empty)', VarIsClear(v), False);

  { VarToStr / VarToStrDef read the private tag too. }
  v := Unassigned;
  if VarToStr(v) <> '' then Fail('VarToStr(Unassigned)', VarToStr(v), '(empty)');
  if VarToStrDef(v, 'dflt') <> 'dflt' then
    Fail('VarToStrDef(Unassigned)', VarToStrDef(v, 'dflt'), 'dflt');
  v := 'xy';
  if VarToStr(v) <> 'xy' then Fail('VarToStr(string)', VarToStr(v), 'xy');
  v := 'x';
  if VarToStr(v) <> 'x' then Fail('VarToStr(1-char)', VarToStr(v), 'x');

  { VarCompareValue compares raw tags internally; the one-char/multi-char pair
    is the case that would break if it had been left on the public codes. }
  CheckB('cmp ''x'' = ''x''', VarCompareValue('x', 'x') = vrEqual, True);
  CheckB('cmp ''x'' < ''y''', VarCompareValue('x', 'y') = vrLessThan, True);
  CheckB('cmp ''x'' vs ''xy''', VarCompareValue('x', 'xy') = vrLessThan, True);
  CheckB('cmp 1 = 1', VarCompareValue(1, 1) = vrEqual, True);
  CheckB('cmp 1 < 2', VarCompareValue(1, 2) = vrLessThan, True);

  if failures = 0 then
    WriteLn('VARTYPECODES OK')
  else
    WriteLn('VARTYPECODES FAILED ', failures);
end.
