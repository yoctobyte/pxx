{ Format's %g and %e against FPC. Every expectation below was read off an FPC
  build of this same file, so it compiles and passes under both.

  Scope: the EXPLICIT-precision forms, which are a contract; the shape of the
  exponential spelling; and, since 2026-08-04, the NO-precision forms and the
  extreme magnitudes. Those last two were excluded while both specifiers
  scaled a double by powers of ten -- one rounding per step, a hundred of them
  for 1e100 -- so 17 correct digits were out of reach. They are reachable now
  that FmtExponent uses the same exact expansion FloatToStr already had.

  TYPE THE OPERANDS. Every float below goes through a `Double` variable, never
  a bare literal: FPC types an untyped real literal as EXTENDED (80-bit), so
  `Format('%e', [3.14159])` compares an Extended against our Double and the
  rows differ for a reason that is not a bug. That confound cost a wrong
  reading once already.

  FPC's precision for BOTH specifiers counts SIGNIFICANT DIGITS, not decimals,
  and clamps at a minimum of two — `%.1g` of 1/3 is `0.33`, and `%.0e` is
  `3.3E-001`. That is measured, and it is the rule this test pins. }
program lib_format_ge;
uses sysutils;

var fails: Integer;
    d: Double;

procedure Chk(const what, got, want: AnsiString);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=[', got, '] want=[', want, ']'); fails := fails + 1; end;
end;

begin
  fails := 0;
  { %g — precision is significant digits }
  Chk('g3',      Format('%.3g',  [1/3]),          '0.333');
  Chk('g6',      Format('%.6g',  [1/3]),          '0.333333');
  { clamped at two, not one }
  Chk('gmin',    Format('%.1g',  [1/3]),          '0.33');
  Chk('g0',      Format('%.0g',  [1/3]),          '0.33');
  { the general form switches to exponential outside the window, and the
    window MOVES with the requested precision }
  Chk('gexp',    Format('%.3g',  [0.000000123]),  '1.23E-7');
  Chk('gbig',    Format('%.3g',  [1e20]),         '1E20');
  Chk('gplain',  Format('%.4g',  [2.5]),          '2.5');
  Chk('gzero',   Format('%.4g',  [0.0]),          '0');
  Chk('gneg',    Format('%.4g',  [-2.5]),         '-2.5');

  { %e — the third exponential spelling: always-signed, at least three
    exponent digits. Before this it had no branch at all and was emitted
    literally. }
  Chk('e4',      Format('%.4e',  [1/3]),          '3.333E-001');
  Chk('e2',      Format('%.2e',  [1/3]),          '3.3E-001');
  Chk('emin',    Format('%.0e',  [1/3]),          '3.3E-001');
  Chk('epos',    Format('%.3e',  [2.5]),          '2.50E+000');
  Chk('eneg',    Format('%.3e',  [-2.5]),         '-2.50E+000');
  Chk('ezero',   Format('%.3e',  [0.0]),          '0.00E+000');
  Chk('ebig',    Format('%.3e',  [1e20]),         '1.00E+020');
  Chk('esmall',  Format('%.3e',  [1e-20]),        '1.00E-020');
  { a three-digit exponent stays three digits, and a larger one grows }
  Chk('ehuge',   Format('%.2e',  [1e300]),        '1.0E+300');

  { the bug that made %e worse than useless: an unknown specifier was emitted
    literally AND did not advance the argument index, so one %e shifted every
    argument after it }
  Chk('advance', Format('%.2e and %d', [1.5, 7]), '1.5E+000 and 7');
  Chk('advance2',Format('%d then %.2e', [7, 1.5]), '7 then 1.5E+000');

  { ---- NO precision: 17 significant digits, the count that round-trips a
    Double. We printed 15 until the exact expansion landed. ---- }
  d := 3.14159;
  Chk('e-default',  Format('%e', [d]), '3.1415899999999999E+000');
  Chk('g-default',  Format('%g', [d]), '3.1415899999999999');

  { ---- EXTREME MAGNITUDES, which is where scaling a double by ten a hundred
    times went visibly wrong: 1e100 printed as 1.0000000000000007E+100, and
    1e200 came out with the wrong EXPONENT. Cross-checked against CPython as
    well as FPC, since the two had to agree before either was trusted. ---- }
  d := 1e100;
  Chk('e-1e100',    Format('%e', [d]), '1.0000000000000000E+100');
  d := 2.5e100;
  Chk('e-2.5e100',  Format('%e', [d]), '2.4999999999999999E+100');
  d := 1e-100;
  Chk('e-1e-100',   Format('%e', [d]), '1.0000000000000000E-100');
  { the exponent itself was wrong here: this value is just UNDER 1e200 }
  d := 1e200;
  Chk('e-1e200',    Format('%e', [d]), '9.9999999999999997E+199');
  Chk('g-1e200',    Format('%g', [d]), '9.9999999999999997E199');
  d := 123456789012345.0;
  Chk('e-15digit',  Format('%e', [d]), '1.2345678901234500E+014');
  { a subnormal -- no normalised exponent exists, so a scaling loop has nothing
    to converge on; the exact expansion does not care }
  d := 1e-320;
  Chk('e-subnormal',Format('%e', [d]), '9.9998886718268301E-321');
  d := 0.0;
  Chk('e-zero',     Format('%e', [d]), '0.0000000000000000E+000');
  d := -2.5;
  Chk('e-neg',      Format('%e', [d]), '-2.5000000000000000E+000');

  if fails = 0 then WriteLn('FORMATGE OK')
  else WriteLn('FORMATGE FAILED ', fails);
end.
