program test_str_dispatch_matches_write;
{ `Str(x, s)` and `write(x)` must render one value ONE way. They did not: Str
  carried a hand-written copy of write's dispatch table and was short a case
  every time anyone looked -- a QWord >= 2^63 came out `-1`, a Boolean came out
  `1`, and (measured 2026-09-05) a STRING came out as its heap address rendered
  as digits while a Char came out as its ordinal. fpc 3.2.2 refuses Str on a
  string and ICEs on a Char, so nothing depended on either answer.

  Str now calls TextStrArg, which IS write's table, so this test is really
  asserting that there is only one table left. Asserted as PAIRS so a divergence
  names the type. The float default is the one thing Str does NOT take from
  write -- no width means FPC's scientific form -- and it has its own row. }
var
  d: Double; n: Integer; i64: Int64; q: QWord; b: Boolean;
  s: string; c: Char; t: string; fails: Integer;

procedure Same(const what, a, b: string);
begin
  if a <> b then
  begin
    Inc(fails);
    writeln('DIFFER ', what, ' Str=[', a, '] write=[', b, ']');
  end;
end;

function W(const x: string): string;
begin
  W := x;
end;

begin
  fails := 0;
  d := 3.14159; n := 42; i64 := -1234567890123;
  q := 18446744073709551615; b := True; s := 'ab'; c := 'z';

  { The `write` side of each pair is written as a literal measured from the
    builtin, because capturing stdout from inside the program would test the
    capture. Each was taken from `writeln(x:w)` on this compiler, which phase 3
    established is byte-identical to fpc 3.2.2 -Mdelphi. }
  Str(d, t);      Same('float default', t, W(' 3.1415899999999999E+000'));
  Str(d:8:2, t);  Same('float w:p',     t, W('    3.14'));
  Str(n, t);      Same('integer',       t, W('42'));
  Str(n:5, t);    Same('integer w',     t, W('   42'));
  Str(i64, t);    Same('int64',         t, W('-1234567890123'));
  Str(q, t);      Same('qword',         t, W('18446744073709551615'));
  Str(b, t);      Same('boolean',       t, W('TRUE'));
  Str(b:7, t);    Same('boolean w',     t, W('   TRUE'));
  Str(s:5, t);    Same('string w',      t, W('   ab'));
  Str(c:3, t);    Same('char w',        t, W('  z'));

  writeln('fails=', fails);
  writeln('STR DISPATCH OK');
end.
