{ FloatToStr parity with FPC. Every expectation below was produced by an
  FPC-built copy of this same table, not by reading pxx's output back — the
  bug this guards (bug-rtl-floattostr-caps-at-six-decimals-and-zeroes-small-values)
  survived for as long as it did because the round numbers a test reaches for
  are exactly the ones the broken six-decimal rule got right.

  The value-LOSS cases are the ones that matter: 1.23E-7, 1E-20 and 1E-300 all
  used to print as the string `0`. }
{ ANTI-DRIFT PAIR. `compiler/builtin/pylib.pas` holds a renamed COPY of this
  file's exact-decimal core (ExDecDigits / ExDecRound and the correctly-rounded
  parser), because a builtin unit may not `uses sysutils` and moving the core
  down would stop `sysutils.pas` reading — and stepping — as a whole
  (decide-nilpy-where-the-exact-decimal-float-core-lives). The copy is exercised
  by `test/test_nilpy_float_repr.npy` against CPython over the same values, so a
  divergence between the two is a test failure here or there rather than a
  discovery years later. CHANGE ONE, CHANGE BOTH. }
program lib_floattostr;
uses sysutils;

var fails: Integer;

procedure Chk(const what, got, want: AnsiString);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

{ bit-for-bit Double equality — the round-trip cases are about landing on the
  SAME double, so comparing rendered text would beg the question }
procedure ChkD(const what: AnsiString; got, want: Double);
begin
  if got = want then WriteLn(what, '=ok')
  else begin
    WriteLn(what, ' FAIL got=', FloatToStrExact(got, 17),
                  ' want=', FloatToStrExact(want, 17));
    fails := fails + 1;
  end;
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
  { shortest round-trip: the shortest spelling that reads back identical.
    Each of these is CPython's repr() of the same double. }
  Chk('short254',  FloatToStrShortest(25.4),      '25.4');
  Chk('shortsum',  FloatToStrShortest(0.1 + 0.2), '0.30000000000000004');
  Chk('shorttenth',FloatToStrShortest(0.1),       '0.1');
  Chk('shortthird',FloatToStrShortest(1/3),       '0.3333333333333333');
  Chk('shortmax',  FloatToStrShortest(1.7976931348623157e308),
                                                  '1.7976931348623157E308');
  Chk('shortden',  FloatToStrShortest(5.0e-324),  '5E-324');

  { ---- StrToFloat correctly rounded (bug-b-strtofloat-not-correctly-rounded).
    The parser used to accumulate in doubles — one rounding per fractional
    digit, and 10^e built by e successive multiplies — so it landed near the
    right double rather than on it. These expectations are CPython's float(s)
    on the same strings. }
  { the round-trip that the whole exercise is for: write exact, read back same }
  ChkD('rt_third',  StrToFloat(FloatToStrExact(1/3, 17)),                1/3);
  ChkD('rt_sum',    StrToFloat(FloatToStrExact(0.1 + 0.2, 17)),          0.1 + 0.2);
  ChkD('rt_254',    StrToFloat(FloatToStrExact(25.4, 17)),               25.4);
  ChkD('rt_e300',   StrToFloat(FloatToStrExact(1e-300, 17)),             1e-300);
  ChkD('rt_max',    StrToFloat(FloatToStrExact(1.7976931348623157e308, 17)),
                                                  1.7976931348623157e308);
  ChkD('rt_den',    StrToFloat(FloatToStrExact(5.0e-324, 17)),           5.0e-324);
  { and via the shortest form, which is the one a program would actually print }
  ChkD('rts_third', StrToFloat(FloatToStrShortest(1/3)),                 1/3);
  ChkD('rts_max',   StrToFloat(FloatToStrShortest(1.7976931348623157e308)),
                                                  1.7976931348623157e308);
  ChkD('rts_den',   StrToFloat(FloatToStrShortest(5.0e-324)),            5.0e-324);
  { half-even at the tie: 2^53+1 is exactly between 2^53 and 2^53+2 }
  Chk('tie_2p53',  FloatToStrExact(StrToFloat('9007199254740993'), 17),
                                                  '9007199254740992');
  { the value that famously hung Java's and PHP's strtod }
  Chk('php_hang',  FloatToStrExact(StrToFloat('2.2250738585072011e-308'), 17),
                                                  '2.2250738585072009E-308');
  { more digits than any double needs, and a magnitude far past the fast path }
  Chk('bignum',    FloatToStrExact(StrToFloat('123456789012345678901234567890'), 17),
                                                  '1.2345678901234568E29');
  Chk('tinylit',   FloatToStrExact(StrToFloat('0.000000000000000000000000001'), 17),
                                                  '1E-27');
  { out of range saturates the way CPython's float() does }
  Chk('ovf',       FloatToStrExact(StrToFloat('1e999'), 17),   'Inf');
  Chk('unf',       FloatToStrExact(StrToFloat('1e-999'), 17),  '0');
  { the acceptance contract must not have moved: malformed still yields def }
  ChkD('bad_e',    StrToFloatDef('1e', -999.0),    -999.0);
  ChkD('bad_txt',  StrToFloatDef('abc', -999.0),   -999.0);
  ChkD('bad_two',  StrToFloatDef('1.2.3', -999.0), -999.0);
  ChkD('bad_sp',   StrToFloatDef('1 2', -999.0),   -999.0);
  ChkD('ok_lead',  StrToFloatDef('000123.4500', -999.0), 123.45);
  ChkD('ok_exp',   StrToFloatDef('1.2E+003', -999.0),    1200.0);
  { The SHARED TABLE — the same values test_nilpy_float_repr.npy runs through
    the pylib copy. Layout differs by design (Pascal's window vs Python's), so
    what is pinned here is the DIGITS and the round trip, which is what the two
    cores actually share. }
  Chk('sh_third',  FloatToStrShortest(1/3),           '0.3333333333333333');
  Chk('sh_e20',    FloatToStrShortest(1e-20),         '1E-20');
  Chk('sh_3e5',    FloatToStrShortest(3.0e-5),        '3E-5');
  Chk('sh_123',    FloatToStrShortest(123456789.123), '123456789.123');
  Chk('sh_sum',    FloatToStrShortest(0.1 + 0.2),     '0.30000000000000004');
  Chk('sh_2third', FloatToStrShortest(1/3 + 1/3),     '0.6666666666666666');
  ChkD('sh_p308',  StrToFloat('1e308'),                             1e308);
  ChkD('sh_pthird',StrToFloat('0.3333333333333333'),   0.3333333333333333);
  ChkD('sh_pden',  StrToFloat('5e-324'),                           5e-324);
  if fails = 0 then WriteLn('FLOATTOSTR OK')
  else WriteLn('FLOATTOSTR FAILED ', fails);
end.
