{ Log10/Log2/LogN must land exactly on the integer for exact powers of the base.

  Ln USED to be a series expansion whose Ln(x)/Ln(base) quotient came out a hair
  BELOW the integer — Log10(1000) was 2.9999999999999996, which made the
  universal digit-count idiom Trunc(Log10(n)) + 1 wrong for nearly every power
  of ten, and right for 1e5 by luck (bug-rtl-log10-is-inexact-for-powers-of-ten).
  That was first fixed by a SnapLog special case; the double-double port then
  DELETED SnapLog, because the dd core hits the integers structurally. This test
  did not change across that swap, which is the point of having it: it pins the
  behaviour, not the mechanism.

  The decimal powers below are spelled as LITERALS, not built by multiplying:
  the original fix reconstructed base^k to decide whether to snap, so building
  the inputs the same way would have tested that code against itself. Powers of two are built by
  doubling, which is exact in IEEE and independent of any decimal rounding.

  The negative half matters as much as the positive: a value a hair off a power
  of ten must NOT be snapped, or the fix would be flattening real values. }
program lib_log_exactness;
uses math, sysutils;

const
  P10: array[0..22] of Double = (
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22);
  N10: array[1..22] of Double = (
    1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9, 1e-10, 1e-11,
    1e-12, 1e-13, 1e-14, 1e-15, 1e-16, 1e-17, 1e-18, 1e-19, 1e-20, 1e-21, 1e-22);

var
  failures: Integer;

procedure Check(ok: Boolean; const what: string);
begin
  if not ok then
  begin
    writeln('FAIL: ', what);
    failures := failures + 1;
  end;
end;

procedure CheckEq(got, want: Double; const what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got ', got:0:17, ' want ', want:0:17);
    failures := failures + 1;
  end;
end;

var
  k: Integer;
  x, e: Double;
begin
  failures := 0;

  { --- Log10 on exact powers of ten, both signs of the exponent --- }
  for k := 0 to 22 do
  begin
    e := k;
    CheckEq(Log10(P10[k]), e, 'Log10(1e' + IntToStr(k) + ')');
    { the idiom the bug actually broke }
    Check(Trunc(Log10(P10[k])) = k, 'Trunc(Log10(1e' + IntToStr(k) + '))');
  end;
  for k := 1 to 22 do
  begin
    e := -k;
    CheckEq(Log10(N10[k]), e, 'Log10(1e-' + IntToStr(k) + ')');
  end;

  { --- Log2 on exact powers of two, both signs --- }
  x := 1.0;
  for k := 0 to 1020 do
  begin
    e := k;
    CheckEq(Log2(x), e, 'Log2(2^' + IntToStr(k) + ')');
    x := x * 2.0;
  end;
  x := 1.0;
  for k := 1 to 1020 do
  begin
    x := x / 2.0;
    e := -k;
    CheckEq(Log2(x), e, 'Log2(2^-' + IntToStr(k) + ')');
  end;

  { --- LogN, arbitrary integer bases --- }
  CheckEq(LogN(2.0, 8.0), 3.0, 'LogN(2,8)');
  CheckEq(LogN(10.0, 1000.0), 3.0, 'LogN(10,1000)');
  CheckEq(LogN(3.0, 81.0), 4.0, 'LogN(3,81)');
  CheckEq(LogN(7.0, 343.0), 3.0, 'LogN(7,343)');
  CheckEq(LogN(10.0, 0.001), -3.0, 'LogN(10,0.001)');
  CheckEq(LogN(2.0, 1.0), 0.0, 'LogN(2,1)');

  { --- values NEAR a power must keep their own value, not be flattened --- }
  Check(Log10(10.000000001) > 1.0, 'Log10(10.000000001) > 1');
  Check(Log10(99.99999999) < 2.0, 'Log10(99.99999999) < 2');
  Check(Log10(100001.0) > 5.0, 'Log10(100001.0) > 5');
  Check(Log2(1023.0) < 10.0, 'Log2(1023) < 10');
  Check(Log2(1025.0) > 10.0, 'Log2(1025) > 10');

  { --- ordinary values still agree with libm to ~1e-15 --- }
  Check(Abs(Log10(2.0) - 0.30102999566398120) < 1e-15, 'Log10(2)');
  Check(Abs(Log10(3.0) - 0.47712125471966244) < 1e-15, 'Log10(3)');
  Check(Abs(Log2(3.0) - 1.58496250072115600) < 1e-15, 'Log2(3)');
  Check(Abs(Log10(0.3) + 0.52287874528033760) < 1e-15, 'Log10(0.3)');

  { --- IEEE edges survive the snap: Ln(0) = -Inf, Ln(negative) = NaN --- }
  Check(Log10(0.0) < -1e300, 'Log10(0) = -Inf');
  x := Log10(-1.0);
  Check(x <> x, 'Log10(-1) = NaN');
  x := Log2(-2.0);
  Check(x <> x, 'Log2(-2) = NaN');

  if failures = 0 then writeln('LOGEXACT OK')
  else writeln('LOGEXACT ', failures, ' FAILURES');
end.
