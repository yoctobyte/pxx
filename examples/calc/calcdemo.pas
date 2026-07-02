{ SPDX-License-Identifier: 0BSD }
program CalcDemo;
{ Deterministic oracle for the calc unit (Track B).

  Evaluates a fixed set of integer expressions and checks exact results, plus a
  few that must be rejected (div-by-zero, bad syntax). Integer-deterministic, so
  output is byte-identical across targets. Ends 'ALL OK' iff all match. }

uses calc, sysutils;

var
  ok: Boolean;

{ Expect expr to evaluate (ok) to want. }
procedure ChkOk(const expr: AnsiString; want: Int64);
var got: Int64; good: Boolean;
begin
  got := Eval(expr, good);
  write(expr, ' = ', got);
  if (not good) or (got <> want) then
  begin
    ok := False;
    write('   FAIL: want ', want, ' (ok=', good, ')');
  end;
  writeln;
end;

{ Expect expr to be rejected. }
procedure ChkErr(const expr: AnsiString);
var good: Boolean;
begin
  Eval(expr, good);
  write(expr, ' -> ');
  if good then begin ok := False; write('FAIL: expected error'); end
  else write('rejected (ok)');
  writeln;
end;

begin
  ok := True;

  { precedence + parens }
  ChkOk('2+3*4', 14);
  ChkOk('(2+3)*4', 20);
  ChkOk('2*3+4*5', 26);
  ChkOk('100/7', 14);
  ChkOk('100%7', 2);
  ChkOk('2*(3+(4-1))*2', 24);

  { unary minus }
  ChkOk('-5+3', -2);
  ChkOk('-(2+3)*2', -10);
  ChkOk('3 - -4', 7);

  { functions }
  ChkOk('gcd(48,36)', 12);
  ChkOk('gcd(48, 36) + 1', 13);
  ChkOk('min(7,3)*max(2,9)', 27);
  ChkOk('pow(2,10)', 1024);
  ChkOk('abs(-42)', 42);
  ChkOk('gcd(pow(2,6), pow(2,4))', 16);
  ChkOk('max(gcd(12,18), min(10,4))', 6);

  { whitespace }
  ChkOk('  12  +  30  ', 42);

  { rejections }
  ChkErr('1/0');
  ChkErr('5%0');
  ChkErr('2+');
  ChkErr('(2+3');
  ChkErr('gcd(1)');
  ChkErr('2 3');
  ChkErr('foo(1,2)');

  writeln;
  if ok then writeln('ALL OK') else writeln('FAILURES');
end.
