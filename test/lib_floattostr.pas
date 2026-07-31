{ FloatToStr parity with FPC. Every expectation below was produced by an
  FPC-built copy of this same table, not by reading pxx's output back — the
  bug this guards (bug-rtl-floattostr-caps-at-six-decimals-and-zeroes-small-values)
  survived for as long as it did because the round numbers a test reaches for
  are exactly the ones the broken six-decimal rule got right.

  The value-LOSS cases are the ones that matter: 1.23E-7, 1E-20 and 1E-300 all
  used to print as the string `0`. }
program lib_floattostr;
uses sysutils;

var fails: Integer;

procedure Chk(const what, got, want: AnsiString);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

begin
  fails := 0;
  { significant digits, not decimal places }
  Chk('third',    FloatToStr(1/3),                '0.333333333333333');
  Chk('pi',       FloatToStr(3.14159265358979),   '3.14159265358979');
  Chk('small',    FloatToStr(0.000123456),        '0.000123456');
  { the value-loss cases: these returned '0' }
  Chk('e7',       FloatToStr(0.000000123),        '1.23E-7');
  Chk('e20',      FloatToStr(1e-20),              '1E-20');
  Chk('e300',     FloatToStr(1e-300),             '1E-300');
  Chk('nege7',    FloatToStr(-0.000000123),       '-1.23E-7');
  { the fixed/exponential window: FPC switches above 15 digits before the point }
  Chk('e15',      FloatToStr(1e15),               '1E15');
  Chk('e16',      FloatToStr(1e16),               '1E16');
  Chk('e19',      FloatToStr(1e19),               '1E19');
  Chk('e20p',     FloatToStr(1e20),               '1E20');
  Chk('max15',    FloatToStr(999999999999999.0),  '999999999999999');
  { and the plain values the six-decimal rule already got right }
  Chk('half',     FloatToStr(2.5),                '2.5');
  Chk('neghalf',  FloatToStr(-2.5),               '-2.5');
  Chk('hundred',  FloatToStr(100.0),              '100');
  Chk('one',      FloatToStr(1.0),                '1');
  Chk('zero',     FloatToStr(0.0),                '0');
  Chk('tenth',    FloatToStr(0.1),                '0.1');
  Chk('tenk',     FloatToStr(0.0001),             '0.0001');
  Chk('mixed',    FloatToStr(1234567890.12345),   '1234567890.12345');
  { explicit-precision paths are a contract and must not have moved }
  Chk('fixed15',  Format('%.15f', [1/3]),         '0.333333333333333');
  Chk('fixed2',   Format('%f', [1/3]),            '0.33');
  if fails = 0 then WriteLn('FLOATTOSTR OK')
  else WriteLn('FLOATTOSTR FAILED ', fails);
end.
