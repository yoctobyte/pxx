{ `String(p)` on a PChar was rejected -- `error: String(): operand must be Char
  or string` -- while every OTHER spelling of the same NUL-terminated-to-Pascal
  conversion worked:

    t := AnsiString(p);   { fine }
    t := p;               { fine }
    t := StrPas(p);       { fine }
    t := String(p);       { error }

  One concept, four spellings, and the broken one is the spelling FPC code
  actually writes. `String` is a KEYWORD token with its own parser branch, so
  it never reached the identifier-cast path where `ansistring` is handled --
  which is exactly why the divergence survived. See
  devdocs/dev/normalise-dont-special-case.md.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-string-of-a-pchar-is-rejected-while-ansistring-of-it-works }
program test_string_of_pchar;
{$mode objfpc}{$H+}
uses sysutils;

var
  ok, total: Integer;
  s, t: string;
  p: PChar;
  buf: array[0..15] of Char;
  c: Char;
  v: Variant;

procedure ChkS(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

begin
  ok := 0; total := 0;
  s := 'hello';
  p := PChar(s);
  buf := 'abc'#0'xyz'#0#0#0#0#0#0#0#0#0;

  { ---- the spelling that was rejected ---- }
  ChkS('String(p)', String(p), 'hello');
  ChkS('String(p + 2)', String(p + 2), 'llo');
  ChkS('String(PChar(@buf[0]))', String(PChar(@buf[0])), 'abc');
  ChkS('String(PChar(s))', String(PChar(s)), 'hello');
  t := String(p);
  ChkS('assigned through', t, 'hello');
  ChkS('concatenated', String(p) + '!', 'hello!');
  ChkS('Length of it', IntToStr(Length(String(p))), '5');
  ChkS('UpperCase of it', UpperCase(String(p)), 'HELLO');

  { ---- the equivalent spellings, which must still agree ---- }
  ChkS('AnsiString(p)', AnsiString(p), 'hello');
  t := p;
  ChkS('implicit t := p', t, 'hello');
  ChkS('StrPas(p)', StrPas(p), 'hello');
  ChkS('all four agree',
       String(p) + '|' + AnsiString(p) + '|' + t + '|' + StrPas(p),
       'hello|hello|hello|hello');

  { ---- an EMPTY C string ---- }
  buf[0] := #0;
  ChkS('String() of an empty C string', '[' + String(PChar(@buf[0])) + ']', '[]');

  { ---- the operands String() already accepted, unchanged ---- }
  ChkS('String of a string', String(s), 'hello');
  c := 'q';
  ChkS('String of a Char', String(c), 'q');
  ChkS('String of a Char literal', String('z'), 'z');
  v := 'vv';
  ChkS('String of a Variant', String(v), 'vv');

  writeln('total ok ', ok, ' / ', total);
end.
