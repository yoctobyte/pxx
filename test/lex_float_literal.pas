{ The float LITERAL must be the nearest double to the text you wrote.

  StrToDoubleBits used to be a rational N/D scaler that halved with
  round-to-odd to stay inside Int64; that composes safely for ONE final
  rounding of an exactly-known value, but every halving here introduced fresh
  error, and 23 of 490 sampled literals came out 1 ULP off
  (bug-a-float-literal-lexer-is-not-correctly-rounded). Silent: a 1-ULP error
  survives every comparison against a nearby value and shows up only in a round
  trip or a bit pattern.

  Each row below is a literal beside the SAME text read by the correctly-rounded
  parser. They must be the same double — that identity is what "correctly
  rounded" means here, and it is also the anti-drift check between
  compiler/exdec.inc and lib/rtl/sysutils.pas, which are copies of one core.
  Every value listed by name is one the sweep caught. }
program lex_float_literal;
uses sysutils;

var fails: Integer;

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
  { the decades the sweep caught — all were 1 ULP low }
  ChkD('e292',  StrToFloat('1e-292'),  1e-292);
  ChkD('e285',  StrToFloat('1e-285'),  1e-285);
  ChkD('e229',  StrToFloat('1e-229'),  1e-229);
  ChkD('e222',  StrToFloat('1e-222'),  1e-222);
  ChkD('e215',  StrToFloat('1e-215'),  1e-215);
  ChkD('e208',  StrToFloat('1e-208'),  1e-208);
  ChkD('m236',  StrToFloat('9.87654321e-236'), 9.87654321e-236);
  ChkD('p135',  StrToFloat('9.87654321e135'),  9.87654321e135);
  { random bit patterns the sweep caught, positive and negative }
  ChkD('r1', StrToFloat('-3.799606243167532e-86'),  -3.799606243167532e-86);
  ChkD('r2', StrToFloat('-5.960149450611519e-274'), -5.960149450611519e-274);
  ChkD('r3', StrToFloat('-8.649571702360239e-175'), -8.649571702360239e-175);
  ChkD('r4', StrToFloat('7.008480465119292e+242'),  7.008480465119292e+242);
  ChkD('r5', StrToFloat('4.617296498014038e-275'),  4.617296498014038e-275);
  ChkD('r6', StrToFloat('5.12574242945416e-51'),    5.12574242945416e-51);
  ChkD('r7', StrToFloat('7.146913570008575e+62'),   7.146913570008575e+62);
  ChkD('r8', StrToFloat('-3.304503820810574e+145'), -3.304503820810574e+145);
  { the extremes and the ordinary values, which were already right and must
    stay right — a correctness fix that moves a correct value is a regression }
  ChkD('tenth',  StrToFloat('0.1'),   0.1);
  ChkD('third',  StrToFloat('0.3333333333333333'), 0.3333333333333333);
  ChkD('half',   StrToFloat('0.5'),   0.5);
  ChkD('two',    StrToFloat('2.0'),   2.0);
  ChkD('e300',   StrToFloat('1e-300'), 1e-300);
  ChkD('den',    StrToFloat('5e-324'), 5e-324);
  ChkD('dmin',   StrToFloat('2.2250738585072014e-308'), 2.2250738585072014e-308);
  ChkD('dmax',   StrToFloat('1.7976931348623157e308'), 1.7976931348623157e308);
  ChkD('big19',  StrToFloat('9223372036854775808.0'), 9223372036854775808.0);
  ChkD('neg',    StrToFloat('-1.5'), -1.5);
  ChkD('zero',   StrToFloat('0.0'), 0.0);
  if fails = 0 then WriteLn('LEXFLOAT OK')
  else WriteLn('LEXFLOAT FAILED ', fails);
end.
