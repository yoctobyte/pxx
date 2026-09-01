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
  spellings, which is what the new tkAssign condition leaves alone. }

type
  TI = Integer;
  TC = Char;
  TS = AnsiString;
  TRec = record a, b: Integer; end;
  PRec = ^TRec;
  TArr = array[0..3] of Integer;
  PArr = ^TArr;

var
  bad: Integer;
  i: Integer; c: Char; s: AnsiString;
  r: TRec; pr: PRec; a: TArr; pa: PArr;

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

  { POINTER aliases must still take the pointer walk, suffixes and all }
  r.a := 0; r.b := 0; pr := @r;
  PRec(pr)^.a := 11;             ChkI('ptr-alias-field', r.a, 11);
  pa := @a;
  PArr(pa)^[2] := 22;            ChkI('ptr-alias-index', a[2], 22);

  if bad = 0 then WriteLn('ALIAS CAST TARGET OK')
  else WriteLn('ALIAS CAST TARGET FAILED ', bad);
end.
