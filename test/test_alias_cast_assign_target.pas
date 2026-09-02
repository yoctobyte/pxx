program test_alias_cast_assign_target;
{ `TAlias(v) := x` where TAlias is a NON-POINTER named type alias.

  THE STRING ROW IS THE ONE THIS FILE EXISTS FOR. `type TS = AnsiString;
  TS(s) := 'z'` used to store a managed string through a POINTER-shaped target:
  the statement-level alias-cast arm is entered on FindTypeAlias, which finds
  every named alias, and then stamped AN_PTR_CAST / tyPointer unconditionally.
  The descriptor was written raw and the refcount release/addref skipped, so
  the target came back with a garbage length (measured: 1073741824) and reading
  it walked off into the heap -- with NO diagnostic. fpc 3.2.2 is the oracle
  here and prints `z`.

  The INT and CHAR rows are not decoration: they went through that same arm and
  were already CORRECT, which is why the fix is scoped to managed strings
  instead of re-routing every non-pointer alias. If a later change widens that
  scope, these two rows are what must keep agreeing with FPC.

  The POINTER-alias rows are the other side of the same guard: those genuinely
  ARE pointer casts and must keep using the walk, including the suffixed
  spellings, which is what the new tkAssign condition leaves alone.

  THE SETLENGTH ROWS (2026-09-02) are the same concept reached through a fourth
  door: `SetLength(TS(s), n)` means `SetLength(s, n)`, because a cast to a string
  type is a value-level no-op and there is nothing for a resize to reinterpret.
  All three spellings used to fail, each differently -- the BUILTIN one died at
  parse time (`undefined variable (AnsiString)`) and both alias ones reached IR
  codegen and died there (`SetLength expects a string variable`), because that
  lowering wants an IR_LEA and a cast node is not one. The control for that group is
  test_setlength_cast_refusal.pas -- an INT alias cast must still be REFUSED, so
  the drop is scoped to string TYPES rather than to casts. It lives in its own
  file because what it asserts is a compile-time refusal. }

type
  TI = Integer;
  TC = Char;
  TS = AnsiString;
  TRec = record a, b: Integer; end;
  PRec = ^TRec;
  TArr = array[0..3] of Integer;
  PArr = ^TArr;
  TFz = String[20];
  TSRec = record f: TS; end;
  PSRec = ^TSRec;

var
  bad: Integer;
  i: Integer; c: Char; s: AnsiString;
  r: TRec; pr: PRec; a: TArr; pa: PArr;
  fz: TFz; sr: TSRec; psr: PSRec;

procedure Chk(const name, got, want: AnsiString);
begin
  if got = want then WriteLn('ok   ', name, ' = ', got)
  else begin WriteLn('FAIL ', name, ' got [', got, '] want [', want, ']'); Inc(bad); end;
end;

procedure ChkI(const name: AnsiString; got, want: Integer);
begin
  if got = want then WriteLn('ok   ', name, ' = ', got)
  else begin WriteLn('FAIL ', name, ' got ', got, ' want ', want); Inc(bad); end;
end;

begin
  bad := 0;

  { non-pointer aliases as a whole assignment target }
  i := 0;     TI(i) := 5;        ChkI('int-alias',   i, 5);
  c := 'a';   TC(c) := 'q';      Chk ('char-alias',  c, 'q');
  s := 'abc'; TS(s) := 'z';      Chk ('str-alias',   s, 'z');
  { the length is the part that was garbage, so assert it separately -- a
    comparison against 'z' alone could pass on a string that merely starts
    with the right byte. }
  ChkI('str-alias-len', Length(s), 1);
  { and again over a longer value, so a one-byte answer cannot fake it }
  s := 'abc'; TS(s) := 'wxyz';   Chk ('str-alias-4',  s, 'wxyz');
  ChkI('str-alias-4-len', Length(s), 4);
  { assigning a VARIABLE, not a literal: the refcount path, not the constant one }
  s := 'abc'; TS(s) := c + 'k';  Chk ('str-alias-var', s, 'qk');

  { SETLENGTH through a string-type cast -- the fourth spelling of the no-op }
  s := 'abc';   SetLength(TS(s), 2);          Chk ('set-alias',      s, 'ab');
  ChkI('set-alias-len', Length(s), 2);
  s := 'abc';   SetLength(AnsiString(s), 1);  Chk ('set-builtin',    s, 'a');
  sr.f := 'hello'; psr := @sr;
  SetLength(TS(psr^.f), 3);                   Chk ('set-alias-fld',  sr.f, 'hel');
  fz := 'hello'; SetLength(TFz(fz), 4);       Chk ('set-frozen',     fz, 'hell');

  { POINTER aliases must still take the pointer walk, suffixes and all }
  r.a := 0; r.b := 0; pr := @r;
  PRec(pr)^.a := 11;             ChkI('ptr-alias-field', r.a, 11);
  pa := @a;
  PArr(pa)^[2] := 22;            ChkI('ptr-alias-index', a[2], 22);

  if bad = 0 then WriteLn('ALIAS CAST TARGET OK')
  else WriteLn('ALIAS CAST TARGET FAILED ', bad);
end.
