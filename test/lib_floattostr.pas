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

  { ---- exact expansion (bug-b-floattostrsig-caps-at-15-significant-digits).
    Every expectation here is CPython's `'%.17g' % v` / `'%.16g' % v` on the
    same double — an oracle, not pxx's own output read back. These are the
    digits FloatToStrSig structurally could not produce: it normalises by
    scaling in doubles, so past 15 the scaling itself is the error. }
  Chk('x17_third', FloatToStrExact(1/3, 17),      '0.33333333333333331');
  Chk('x16_third', FloatToStrExact(1/3, 16),      '0.3333333333333333');
  Chk('x17_tenth', FloatToStrExact(0.1, 17),      '0.10000000000000001');
  Chk('x17_sum',   FloatToStrExact(0.1 + 0.2, 17),'0.30000000000000004');
  Chk('x17_254',   FloatToStrExact(25.4, 17),     '25.399999999999999');
  Chk('x16_awk',   FloatToStrExact(2.834645669291339, 16), '2.834645669291339');
  { the magnitudes where scaling in doubles hurt most: DBL_MAX and a denormal }
  Chk('x17_max',   FloatToStrExact(1.7976931348623157e308, 17),
                                                  '1.7976931348623157E308');
  Chk('x17_den',   FloatToStrExact(5.0e-324, 17), '4.9406564584124654E-324');
  Chk('x17_e300',  FloatToStrExact(1e-300, 17),   '1E-300');
  { asking for fewer digits still rounds off the EXACT expansion }
  Chk('x3_254',    FloatToStrExact(25.4, 3),      '25.4');
  Chk('x1_third',  FloatToStrExact(1/3, 1),       '0.3');
  { specials keep FloatToStr's spellings }
  Chk('x_zero',    FloatToStrExact(0.0, 17),      '0');
  Chk('x_negsum',  FloatToStrExact(-(0.1 + 0.2), 17), '-0.30000000000000004');
  { FloatToStrSig's own cap is gone: past 15 it defers to the exact path,
    while 15 and below keep the output every other test in the tree pins. }
  Chk('sig17',     FloatToStrSig(1/3, 17),        '0.33333333333333331');
  Chk('sig15',     FloatToStrSig(1/3, 15),        '0.333333333333333');
  { shortest round-trip: the shortest spelling that reads back identical }
  Chk('short254',  FloatToStrShortest(25.4),      '25.4');
  Chk('shortsum',  FloatToStrShortest(0.1 + 0.2), '0.30000000000000004');
  Chk('shorttenth',FloatToStrShortest(0.1),       '0.1');
  if fails = 0 then WriteLn('FLOATTOSTR OK')
  else WriteLn('FLOATTOSTR FAILED ', fails);
end.
