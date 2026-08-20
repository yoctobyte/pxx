{ The other half of test_unary_minus_widens_to_int64.pas, and the line between
  them is CONSTANT vs VARIABLE.

  FPC's unary minus has one result type for a negated VARIABLE — Int64, for
  every integer operand (that is the sibling test). A negated CONSTANT is folded
  first and typed by its VALUE: the smallest signed type that holds it, so `-1`
  is a LongInt and stays one.

  Widening the constant too looked like the same rule and broke three measured
  behaviours at once: `IntToHex(-1, 8)` bound the Int64 overload and printed 16
  digits, `-7` in an `array of const` arrived as vtInt64 so a vtInteger reader
  skipped the entry entirely, and the overload-width table moved its literal row
  to int64. All three came back from the watcher as regressions within the hour
  (regression-test-core-test-asm-emit and its two siblings), which is what this
  test exists to stop happening again.

  Every expected value below is `fpc -O- -Mobjfpc`'s own output for this source.
  bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits }
program test_unary_minus_constant_keeps_longint;
{$mode objfpc}{$H+}
uses sysutils;

function Which(x: longint): string; overload; begin Which := 'longint'; end;
function Which(x: int64): string; overload; begin Which := 'int64'; end;
function Which(x: qword): string; overload; begin Which := 'qword'; end;

const
  K  = 7;
  KB = 4294967295;

var
  b: byte;
  i: integer;
  ok, total: Integer;

procedure Chk(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;
  { a literal, and the two edges of the LongInt range }
  Chk('-1',           Which(-1),           'longint');
  Chk('-2147483647',  Which(-2147483647),  'longint');
  Chk('-2147483648',  Which(-2147483648),  'longint');
  Chk('-2147483649',  Which(-2147483649),  'int64');
  { an unsigned constant negates out of LongInt's range }
  Chk('-4294967295',  Which(-4294967295),  'int64');
  { a NAMED constant is a constant too, and so is an expression over them }
  Chk('-K',           Which(-K),           'longint');
  Chk('-KB',          Which(-KB),          'int64');
  Chk('-(1+2)',       Which(-(1+2)),       'longint');
  Chk('-(K*3)',       Which(-(K*3)),       'longint');
  { ...while a VARIABLE still widens, whatever its width — the sibling rule }
  b := 3;  Chk('-b',  Which(-b),  'int64');
  i := 5;  Chk('-i',  Which(-i),  'int64');
  { the two shapes the regressions surfaced through }
  Chk('IntToHex(-1,8)', IntToHex(-1, 8), 'FFFFFFFF');
  Chk('IntToHex(-i,8)', IntToHex(-i, 8), 'FFFFFFFFFFFFFFFB');
  writeln('total ok ', ok, ' / ', total);
end.
