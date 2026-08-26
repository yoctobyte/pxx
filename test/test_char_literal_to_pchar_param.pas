program test_char_literal_to_pchar_param;
{ A ONE-CHARACTER literal where a PChar is expected.

  `StrCat(buf, '--')` worked and `StrCat(buf, '-')` SEGFAULTED. A one-char
  single-quoted literal parses as an AN_INT_LIT tagged tyChar carrying its
  ORDINAL, so a PChar parameter was handed 45 as the pointer and the callee
  dereferenced address 45. Nothing in the source distinguishes the two
  spellings, so a program worked until someone shortened a separator -- and
  when the ordinal happens to land on a mapped page it is a wrong VALUE rather
  than a crash.

  The rule "a one-character literal is ALSO a one-character string, and the
  CONTEXT decides" was open-coded in four places and no copy knew about a PChar
  parameter; the method-call argument loops had no copy at all. This asserts
  every arm of the shape, and the WORKING shapes beside them, so a future fix
  cannot repair one boundary and break the other.

  bug-single-char-literal-as-pchar-argument-segfaults

  Every row is measured against fpc 3.2.2 -Mobjfpc -Sh, which prints exactly
  these values. A char VARIABLE and `Chr(45)` are deliberately NOT here: FPC
  refuses the variable and const-folds the Chr, so the two shapes want
  different answers and the second half is a dialect-strictness call --
  bug-p-a-char-value-is-accepted-where-a-pchar-is-wanted-and-segfaults. A typed
  `const P: PChar = '-'` is absent for the same reason (a separate machinery,
  broken at every literal length) --
  bug-p-a-typed-pchar-const-cannot-be-initialised-from-a-literal. }
uses sysutils;

const
  Dash  = '-';
  DDash = '--';

type
  TThing = class
    procedure Take(tag: AnsiString; p: PChar);
  end;

var
  fails: Integer;

function Text(p: PChar): AnsiString;
{ read the pointer the way a C callee would: one char at a time to the NUL }
var i: Integer;
begin
  Text := '';
  i := 0;
  while p[i] <> #0 do
  begin
    Text := Text + p[i];
    i := i + 1;
  end;
end;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
    fails := fails + 1;
  end;
end;

procedure ChkB(const what: AnsiString; got, want: Boolean);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

procedure Show(const what: AnsiString; p: PChar);
begin
  ChkS(what, Text(p), '-');
end;

procedure Ov(p: PChar); overload;
begin
  ChkS('overloaded call picks PChar', Text(p), '-');
end;

procedure Ov(i: Integer); overload;
begin
  writeln('FAIL overloaded call picked Integer');
  fails := fails + 1;
end;

function Mid(p: PChar): PChar;
begin
  Mid := p;
end;

procedure TThing.Take(tag: AnsiString; p: PChar);
begin
  ChkS(tag, Text(p), '-');
end;

var
  buf: array[0..63] of Char;
  i: Integer;
  obj: TThing;
  pv: PChar;

begin
  fails := 0;

  { --- the plain call argument, the shape the ticket was filed on --------- }
  Show('one-char literal', '-');
  Show('a #45 literal', #45);
  Show('a named char const', Dash);

  { the two-character control: it always worked, and must keep working }
  ChkS('two-char literal', Text('--'), '--');
  ChkS('a named two-char const', Text(DDash), '--');
  ChkS('the empty literal', Text(''), '');

  { --- overload resolution still reads the argument as the Char it is ----- }
  Ov('-');

  { --- nested in another call's argument ---------------------------------- }
  Show('a call result of a one-char literal', Mid('-'));

  { --- a METHOD argument: these loops never had the coercion at all ------- }
  obj := TThing.Create;
  obj.Take('method argument', '-');
  obj.Free;

  { --- assignment, the boundary that was fixed first: all three spellings - }
  pv := '-';
  ChkS('assigned one-char literal', Text(pv), '-');
  pv := #45;
  ChkS('assigned #45', Text(pv), '-');
  pv := Dash;
  ChkS('assigned a named char const', Text(pv), '-');

  { --- comparison compares CONTENTS, at both lengths and both sides ------- }
  pv := '-';
  ChkB('PChar = one-char literal', pv = '-', True);
  ChkB('one-char literal = PChar', '-' = pv, True);
  ChkB('PChar <> one-char literal', pv <> '-', False);
  ChkB('PChar = a different one-char literal', pv = '+', False);
  pv := '--';
  ChkB('PChar = two-char literal', pv = '--', True);

  { --- and through the RTL PChar family, which is where it was found ------ }
  for i := 0 to 63 do buf[i] := '#';
  StrCopy(@buf[0], 'x');
  StrCat(@buf[0], '-');
  ChkS('StrCopy/StrCat with one-char literals', StrPas(@buf[0]), 'x-');
  ChkS('StrLen of a one-char literal', IntToStr(StrLen('-')), '1');

  for i := 0 to 63 do buf[i] := '#';
  StrCopy(@buf[0], 'xy');
  StrCat(@buf[0], '--');
  ChkS('StrCopy/StrCat with two-char literals', StrPas(@buf[0]), 'xy--');

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
