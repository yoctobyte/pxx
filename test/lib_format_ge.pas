{ Format's %g and %e against FPC. Every expectation below was read off an FPC
  build of this same file, so it compiles and passes under both.

  Scope, deliberately: the EXPLICIT-precision forms, which are a contract, and
  the shape of the exponential spelling. The no-precision forms are NOT here —
  FPC prints 17 significant digits there and we print 15, which needs an exact
  big-integer conversion rather than scaling a double; that gap is recorded in
  compat-pascal-format-g-and-e-specifiers rather than papered over with an
  expectation copied from our own output.

  FPC's precision for BOTH specifiers counts SIGNIFICANT DIGITS, not decimals,
  and clamps at a minimum of two — `%.1g` of 1/3 is `0.33`, and `%.0e` is
  `3.3E-001`. That is measured, and it is the rule this test pins. }
program lib_format_ge;
uses sysutils;

var fails: Integer;

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

  if fails = 0 then WriteLn('FORMATGE OK')
  else WriteLn('FORMATGE FAILED ', fails);
end.
