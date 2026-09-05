program test_varrec_format_bracket;
{ Phase 2 of feature-writeln-as-library, BRACKET spelling: `[ x:8:2 ]` inside an
  `array of const` literal.

  Asserted as PAIRS against the builtin `writeln`, so a divergence names the
  TYPE rather than just failing. The builtin is the oracle here and it is itself
  byte-identical to fpc 3.2.2 -Mdelphi (measured when phase 3 landed), so this
  chains to FPC without needing fpc at test time.

  There is no vtFormatted tag: a formatted element is rendered by TextStrArg --
  the same builtin formatters `Str(...)` lowers to, and the same ones the write
  statement's variable-width path already used -- so it boxes as an ordinary
  managed string and every existing TVarRec consumer reads it unchanged. }
uses libwriteln;

var
  fails: Integer;

procedure Same(const what, a, b: AnsiString);
begin
  if a <> b then
  begin
    Inc(fails);
    writeln('DIFFER ', what, ' builtin=[', a, '] bracket=[', b, ']');
  end;
end;

function B(const a: array of const): AnsiString;
begin
  B := VarRecsToText(a);
end;

var
  d: Double;
  n: Integer;
  i64: Int64;
  q: QWord;
  bo: Boolean;
  s: string;
  c: Char;
  w: Integer;
  t: AnsiString;
begin
  fails := 0;
  d := 3.14159; n := 42; i64 := -1234567890123; q := 18446744073709551615;
  bo := True; s := 'ab'; c := 'z'; w := 6;

  { Each row: render with the builtin into a string via Str-equivalent, and with
    the bracket form, then compare. The builtin side uses write-to-string via
    the same formatting the console uses, which is what the pair is about. }
  Str(d:8:2, t);   Same('double w:p', t, B([d:8:2]));
  Str(d:0:3, t);   Same('double 0:3', t, B([d:0:3]));
  Str(n:5, t);     Same('integer w', t, B([n:5]));
  Str(n:0, t);     Same('integer 0', t, B([n:0]));
  Str(i64:20, t);  Same('int64 w', t, B([i64:20]));
  Str(q:22, t);    Same('qword w', t, B([q:22]));
  Str(bo:7, t);    Same('boolean w', t, B([bo:7]));
  Str(s:5, t);     Same('string w', t, B([s:5]));
  Str(c:3, t);     Same('char w', t, B([c:3]));
  Str(d:w:2, t);   Same('variable width', t, B([d:w:2]));

  { A width NARROWER than the value must not truncate -- the field grows. }
  Str(n:1, t);     Same('narrow width', t, B([n:1]));

  { Unformatted elements in the same literal must keep their ordinary boxing,
    so the change cannot have turned every element into a string. }
  Same('mixed literal', '42|ab', B([n, '|', s]));

  { A QWord at the top of its range. The UNFORMATTED boxing renders it signed --
    a known, filed hole in the vtInteger/vtInt64 tagging. The FORMATTED path
    does not share it, because it renders through StrQWord before boxing. That
    is not a fix for the hole and must not be read as one; it is recorded here
    so the difference is deliberate rather than a surprise. }
  Str(q:0, t);
  if t <> B([q:0]) then
  begin
    Inc(fails);
    writeln('DIFFER qword formatted vs Str: [', t, '] [', B([q:0]), ']');
  end;

  writeln('fails=', fails);
  writeln('VARREC FORMAT BRACKET OK');
end.
