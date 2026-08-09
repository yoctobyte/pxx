{ The Python `math` surface added to lib/rtl/math.pas.

  NilPy's `import math` resolves ordinary names straight against this unit,
  case-insensitively, so these ARE math.e / math.isnan / math.comb — every
  expectation below is CPython's own output for the same call, captured by
  diffing a .npy against python3 until identical.

  FOUR names from the sweep are deliberately absent and are NOT oversights
  (bug-n-math-trunc-and-log-need-frontend-intercepts):

  - `pow`, `log`, `copysign`, `atan2` — adding these to lib/rtl/math.pas
    MEASURES AS A C REGRESSION. pxxcio is auto-pulled into every C program and does `uses math`,
    so every name in that unit is in scope for C name resolution and a Pascal
    Pow/Log/CopySign hijacks libc's: gcc says pow(2,10) = 1024, and with `Pow`
    there a C program said 1, while copysign(3,-1) answered 0.785398 — atan2's
    result. `atan2` was added anyway and shipped broken for one commit
    (cmath_trig_family_b385 red), because the first canary only checked
    atan2(1,1) — symmetric arguments, so a swapped or ignored argument is
    invisible. bug-c-pascal-math-names-hijack-libc-through-pxxcio.
  - `trunc` — CPython returns an INT (-2, not -2.0). A Double->Double Trunc here
    would resolve ahead of everything and hand every caller the wrong type
    quietly, which is worse than the honest "undefined variable". It wants a
    pymath_trunc intercept beside pymath_floor/pymath_ceil.

  `log(x, base)` has a second reason on top: CPython gives 2.9999999999999996
  for log(1000, 10) because it does not snap; FPC's LogN gives exactly 3.0, and
  so does ours. Both are right against their own oracle, so LogN stays
  FPC-faithful and NilPy wants its own intercept either way.

  Inf/NaN are built from IEEE BIT PATTERNS rather than 1.0/0.0 and 0.0/0.0,
  which is asserted here only indirectly — but the reason is worth knowing when
  editing them: the division form raises ZeroDivisionError the moment a NilPy
  program calls math.inf. }
program lib_math_python_surface;

uses math, sysutils;

var
  failures: Integer;

procedure CheckStr(const got, want, what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got <', got, '> want <', want, '>');
    failures := failures + 1;
  end;
end;

procedure Check(ok: Boolean; const what: string);
begin
  if not ok then
  begin
    writeln('FAIL: ', what);
    failures := failures + 1;
  end;
end;

procedure CheckI64(got, want: Int64; const what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

begin
  failures := 0;

  { --- constants. Compared with a tolerance, not FloatToStr: ours prints 15
    significant digits (FPC's default, and correct for FPC parity) where
    CPython's repr prints the shortest round-trip form, so FloatToStr(E) is
    '2.71828182845904' against CPython's '2.718281828459045'. That is a
    formatting difference, not a value difference — the values are identical,
    verified by diffing a .npy against python3. --- }
  Check(Abs(E - 2.718281828459045) < 1e-15, 'math.e');
  Check(Abs(Tau - 6.283185307179586) < 1e-15, 'math.tau');
  Check(Abs(Pi - 3.141592653589793) < 1e-15, 'math.pi');
  Check(Abs(Tau - 2.0 * Pi) < 1e-15, 'tau = 2*pi');

  { --- inf / nan, and the predicates that are the reason they exist --- }
  Check(IsInf(Inf), 'isinf(inf)');
  Check(IsInf(-Inf), 'isinf(-inf)');
  Check(not IsInf(1.0), 'not isinf(1.0)');
  Check(IsNan(NaN), 'isnan(nan)');
  Check(not IsNan(1.0), 'not isnan(1.0)');
  Check(not IsNan(Inf), 'not isnan(inf)');
  Check(Inf > 1.0e308, 'inf is larger than any finite double');
  Check(-Inf < -1.0e308, '-inf is smaller than any finite double');

  { --- logs that DO live here: LogN under its own (reversed-argument) name --- }
  Check(Abs(Ln(E) - 1.0) < 1e-15, 'Ln(e) = 1');
  Check(Abs(LogN(2.0, 8.0) - 3.0) < 1e-15, 'LogN(base, x) — note the order');

  { --- angles --- }
  CheckStr(FloatToStr(Degrees(Pi)), '180', 'math.degrees(pi)');
  Check(Abs(Radians(180.0) - 3.141592653589793) < 1e-15, 'math.radians(180)');
  Check(Abs(Radians(Degrees(1.25)) - 1.25) < 1e-15, 'radians/degrees round trip');
  { atan2 is NOT here — see the header. ArcTan2 is the Pascal spelling and does
    not collide with anything in C. }
  Check(Abs(ArcTan2(0.5, 1.0) - 0.4636476090008061) < 1e-15, 'ArcTan2(0.5, 1)');

  { --- isclose, Python's defaults --- }
  Check(IsClose(1.0, 1.0), 'isclose(1, 1)');
  Check(IsClose(1.0, 1.0000000001), 'isclose within rel_tol 1e-9');
  Check(not IsClose(1.0, 1.1), 'not isclose(1, 1.1)');
  Check(IsClose(Inf, Inf), 'isclose(inf, inf) — equal infinities are close');
  Check(not IsClose(Inf, -Inf), 'not isclose(inf, -inf)');
  Check(not IsClose(NaN, NaN), 'not isclose(nan, nan) — NaN is never close');
  Check(not IsClose(0.0, 1e-12), 'abs_tol defaults to 0, so nothing is close to 0');
  Check(IsClose(0.0, 1e-12, 1.0e-9, 1.0e-9), 'an explicit abs_tol does reach 0');

  { --- integer functions --- }
  CheckI64(Factorial(0), 1, 'factorial(0)');
  CheckI64(Factorial(1), 1, 'factorial(1)');
  CheckI64(Factorial(10), 3628800, 'factorial(10)');
  CheckI64(Factorial(20), 2432902008176640000, 'factorial(20) — the Int64 limit');
  CheckI64(Comb(10, 3), 120, 'comb(10, 3)');
  CheckI64(Comb(5, 0), 1, 'comb(5, 0)');
  CheckI64(Comb(5, 5), 1, 'comb(5, 5)');
  CheckI64(Comb(52, 5), 2598960, 'comb(52, 5) — poker hands');
  CheckI64(Comb(3, 5), 0, 'comb(n, k) with k > n');
  { the multiplicative form must stay exact where n!/(k!(n-k)!) would overflow:
    60! is far past Int64, C(60,30) is not }
  CheckI64(Comb(60, 30), 118264581564861424, 'comb(60, 30) stays exact');

  if failures = 0 then writeln('MATHPY OK')
  else writeln('MATHPY ', failures, ' FAILURES');
end.
