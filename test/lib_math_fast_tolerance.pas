program lib_math_fast_tolerance;
{ The DEFAULT (fast) float path — devdocs/dev/float-policy.md.

  The companion to lib_math_correctly_rounded, which asserts the last bit and
  is built with -dPXX_FLOAT_EXACT. This one asserts what the default mode
  actually promises, and the split matters: a test that demands the last bit
  from the fast path would fail for a reason that is not a defect, and the
  next agent would "fix" it by making the fast path slow again.

  Two different kinds of assertion here, and the difference is the whole point:

  - ACCURACY is a TOLERANCE. Within 2 ulp of glibc, and that is all. 1-2 ulp is
    the cost of arithmetic in 53 bits, it is libm's own contract, and it is
    explicitly NOT a bug.
  - BEHAVIOUR is EXACT. Signed zeros, infinities, NaN, and the sign and
    magnitude of a result are asserted bit for bit in BOTH modes, because those
    are not accuracy — a lost -0 or a NaN where a number belongs is a wrong
    value at any speed.

  The large-argument rows are the ones worth keeping honest. Sin(1e10) was
  2.4 BILLION ulp out before the reduction was fixed, and the fast path uses
  the SAME reduction, so it stays within 2 ulp here. An error that grows with
  the argument is a bug in either mode. }
uses math, sysutils;

type
  PI64 = ^Int64;

var
  failures: Integer;

function Bits(x: Double): Int64;
begin
  Result := PI64(@x)^;
end;

{ ulp distance between two doubles of the same sign, via the monotone bit
  pattern. Only meaningful for finite values, which is all this uses it on. }
function UlpApart(a, b: Double): Int64;
var ba, bb: Int64;
begin
  ba := Bits(a); bb := Bits(b);
  if ba >= bb then Result := ba - bb else Result := bb - ba;
end;

{ accuracy: within `tol` ulp of the reference.

  The reference arrives as a DECIMAL LITERAL, not a hex bit pattern: 17
  significant digits round-trip a double exactly, and the alternative wanted
  StrToInt64('$BFE1...'), which overflows a signed Int64 the moment the sign
  bit is set. Values are glibc's, generated rather than typed. }
procedure CheckUlp(got, want: Double; tol: Int64; const tag: string);
var d: Int64;
begin
  d := UlpApart(got, want);
  if d <= tol then
    writeln(tag, '=ok')
  else
  begin
    writeln(tag, '=FAIL got ', IntToHex(Bits(got), 16), ' want ',
            IntToHex(Bits(want), 16), ' (', d, ' ulp, tolerance ', tol, ')');
    failures := failures + 1;
  end;
end;

{ behaviour: exact, no tolerance. Hex here because the values being asserted
  ARE bit patterns — a signed zero has no distinguishing decimal form. }
procedure CheckExact(got: Double; const wantHex: string; const tag: string);
begin
  if IntToHex(Bits(got), 16) = wantHex then
    writeln(tag, '=ok')
  else
  begin
    writeln(tag, '=FAIL got ', IntToHex(Bits(got), 16), ' want ', wantHex);
    failures := failures + 1;
  end;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok')
  else begin writeln(tag, '=FAIL'); failures := failures + 1; end;
end;

var
  x, z, inf, nan: Double;
begin
  failures := 0;
  z := 0.0;
  inf := 1.0 / z;
  nan := z / z;

  { ---- accuracy: within 2 ulp of glibc, and no more is promised ---- }
  CheckUlp(Sin(0.5), 0.479425538604203, 2, 'sin-0.5');
  CheckUlp(Cos(0.5), 0.8775825618903728, 2, 'cos-0.5');
  CheckUlp(Tan(0.5), 0.5463024898437905, 2, 'tan-0.5');
  CheckUlp(Sin(3.7), -0.5298361409084934, 2, 'sin-3.7');
  CheckUlp(Cos(3.7), -0.848100031710408, 2, 'cos-3.7');
  CheckUlp(Sin(123.456), -0.8039373685728239, 2, 'sin-123');
  CheckUlp(Cos(123.456), -0.5947139710921574, 2, 'cos-123');

  { LARGE arguments. These are the rows that were 85 / 1,220,648 /
    2,461,005,116 ulp out before the reduction was fixed. The fast path shares
    that reduction, so a tolerance of 2 still holds here — and if this ever
    fails by a LARGE number, the reduction has broken, which IS a bug. }
  CheckUlp(Sin(100.0), -0.5063656411097588, 2, 'sin-100');
  CheckUlp(Cos(100.0), 0.8623188722876839, 2, 'cos-100');
  CheckUlp(Sin(1.0e6), -0.34999350217129294, 2, 'sin-1e6');
  CheckUlp(Cos(1.0e6), 0.9367521275331447, 2, 'cos-1e6');
  CheckUlp(Sin(1.0e10), -0.4875060250875107, 2, 'sin-1e10');
  CheckUlp(Cos(1.0e10), 0.873119622676856, 2, 'cos-1e10');
  CheckUlp(Sin(1.0e100), -0.3806377310050287, 2, 'sin-1e100');
  CheckUlp(Cos(1.0e100), 0.9247242387519338, 2, 'cos-1e100');

  { the inverse family, the logs, and Sqrt — which is EXACT even here, because
    it is one hardware instruction on x86-64 and correctly rounded by IEEE
    mandate on the others }
  CheckUlp(ArcSin(0.5), 0.5235987755982989, 2, 'asin-0.5');
  CheckUlp(ArcCos(0.5), 1.0471975511965979, 2, 'acos-0.5');
  CheckUlp(ArcTan(2.0), 1.1071487177940904, 2, 'atan-2');
  CheckUlp(ArcTan2(0.5, 1.0), 0.4636476090008061, 2, 'atan2');
  CheckUlp(Sqrt(2.0), 1.4142135623730951, 0, 'sqrt-2-exact');

  { ---- the log / exp family ----
    Ln and Exp were the WORST ratio in the RTL (1270x glibc) before the fast
    kernels; Log10/Log2/LogN/Sinh all sit on top of them. The large-|x| rows are
    the ones that catch a broken reduction, exactly as with trig: an error here
    grows with the exponent rather than staying at 1-2 ulp. }
  CheckUlp(Ln(2.0), 0.6931471805599453, 2, 'ln-2');
  CheckUlp(Ln(1.0e300), 690.7755278982137, 2, 'ln-1e300');
  CheckUlp(Ln(1.0000001), 9.999999505838704e-08, 2, 'ln-near-1');
  CheckUlp(Exp(1.0), 2.718281828459045, 2, 'exp-1');
  CheckUlp(Exp(-1.0), 0.36787944117144233, 2, 'exp-neg1');
  CheckUlp(Exp(700.0), 1.0142320547350045e+304, 2, 'exp-700');
  CheckUlp(Exp(-700.0), 9.85967654375977e-305, 2, 'exp-neg700');
  CheckUlp(Exp(1.0e-10), 1.0000000001, 2, 'exp-tiny');
  CheckUlp(Log10(2.0), 0.3010299956639812, 2, 'log10-2');
  CheckUlp(Log2(10.0), 3.321928094887362, 2, 'log2-10');
  CheckUlp(Log2(1.0e-300), -996.5784284662087, 2, 'log2-1e-300');
  CheckUlp(LogN(2.0, 8.0), 3.0, 2, 'logn-2-8');
  CheckUlp(Sinh(1.0), 1.1752011936438014, 2, 'sinh-1');
  CheckUlp(Cosh(1.0), 1.5430806348152437, 2, 'cosh-1');
  CheckUlp(Tanh(1.0), 0.7615941559557649, 2, 'tanh-1');

  { ---- the hyperbolic family ----
    All six were the textbook identity written out literally, and every one was
    wrong somewhere: ArcSinh(1e-15) and ArcTanh(1e-15) were 11% off, Sinh(1e-15)
    5% off, ArcSinh(-94) 1497 ulp, ArcCosh(0.5) answered 0.0 for a DOMAIN ERROR,
    and Tanh(800) was NaN where the answer is 1. One cause — a small result
    routed through a quantity near 1 — so the fix was to add expm1/log1p
    underneath rather than patch six formulas.

    These rows are the ones that were wrong. A tolerance failure here is a
    rounding question; a row coming back 5% out, or NaN, is the old bug. }
  CheckUlp(Sinh(1.0e-15), 1e-15, 2, 'sinh-tiny');
  CheckUlp(Tanh(1.0e-15), 1e-15, 2, 'tanh-tiny');
  CheckUlp(ArcSinh(1.0e-15), 1e-15, 2, 'asinh-tiny');
  CheckUlp(ArcTanh(1.0e-15), 1e-15, 2, 'atanh-tiny');
  CheckUlp(ArcSinh(-94.0), -5.23647025497466, 2, 'asinh-negative');
  CheckUlp(ArcTanh(0.5), 0.5493061443340548, 2, 'atanh-half');
  CheckUlp(ArcCosh(1.5), 0.9624236501192069, 2, 'acosh-1p5');
  CheckUlp(Tanh(16.5), 0.9999999999999907, 2, 'tanh-saturating');

  { premature overflow: sinh/cosh(710) are ORDINARY doubles, but 0.5*Exp(710)
    evaluates Exp first and hits Inf. Exp(x - ln2) is the same value. }
  CheckUlp(Sinh(710.0), 1.1169973830808557e+308, 2, 'sinh-710-no-early-overflow');
  CheckUlp(Cosh(710.0), 1.1169973830808557e+308, 2, 'cosh-710-no-early-overflow');
  { x*x overflows past 1.3e154, which used to turn asinh/acosh(1e200) into Inf }
  CheckUlp(ArcSinh(1.0e200), 461.2101657793691, 2, 'asinh-huge-no-x2-overflow');
  CheckUlp(ArcCosh(1.0e200), 461.2101657793691, 2, 'acosh-huge');
  CheckUlp(Power(1.0001, 10000.0), 2.7181459268249255, 2, 'power-amplified');

  { EXACT even in fast mode, and deliberately so: the reductions pull the
    exponent out by bit extraction, which is exact, so a power of the base has
    nothing left to round. People read these values off a screen — Log10(1000)
    printing 2.9999999999999996 is the kind of "correct to 2 ulp" that gets
    filed as a bug. Tolerance 0, not 2. }
  CheckUlp(Log10(1000.0), 3.0, 0, 'log10-1000-exact');
  CheckUlp(Log10(1.0e300), 300.0, 0, 'log10-1e300-exact');
  CheckUlp(Log2(1024.0), 10.0, 0, 'log2-1024-exact');
  CheckUlp(Log2(1.0), 0.0, 0, 'log2-1-exact');
  CheckUlp(Ln(1.0), 0.0, 0, 'ln-1-exact');
  CheckUlp(Exp(0.0), 1.0, 0, 'exp-0-exact');
  CheckUlp(Power(2.0, 10.0), 1024.0, 0, 'power-2-10-exact');

  { ---- behaviour: EXACT in both modes, no tolerance ---- }
  CheckExact(Sin(0.0),  '0000000000000000', 'sin-plus-zero');
  CheckExact(Sin(-z),   '8000000000000000', 'sin-minus-zero');
  CheckExact(Cos(0.0),  '3FF0000000000000', 'cos-plus-zero');
  CheckExact(Cos(-z),   '3FF0000000000000', 'cos-minus-zero');
  CheckExact(Tan(-z),   '8000000000000000', 'tan-minus-zero');
  CheckExact(Sqrt(-z),  '8000000000000000', 'sqrt-minus-zero');
  CheckExact(ArcTan2(-z, -1.0), 'C00921FB54442D18', 'atan2-minus-zero-neg');
  CheckExact(ArcTan2(-z,  1.0), '8000000000000000', 'atan2-minus-zero-pos');

  SayBool('sin-inf-nan', Sin(inf) <> Sin(inf));
  SayBool('cos-inf-nan', Cos(inf) <> Cos(inf));
  SayBool('tan-inf-nan', Tan(inf) <> Tan(inf));
  SayBool('sin-nan-nan', Sin(nan) <> Sin(nan));
  SayBool('sqrt-neg-nan', Sqrt(-1.0) <> Sqrt(-1.0));
  SayBool('asin-domain-nan', ArcSin(2.0) <> ArcSin(2.0));
  SayBool('ln-zero-neginf', Ln(0.0) < -1.0e308);
  SayBool('ln-neg-nan', Ln(-1.0) <> Ln(-1.0));
  SayBool('ln-inf-inf', Ln(inf) > 1.0e308);
  SayBool('log10-zero-neginf', Log10(0.0) < -1.0e308);
  SayBool('log2-zero-neginf', Log2(0.0) < -1.0e308);
  SayBool('log10-neg-nan', Log10(-2.0) <> Log10(-2.0));
  SayBool('exp-inf', Exp(inf) > 1.0e308);
  SayBool('exp-neginf-zero', Exp(-inf) = 0.0);
  SayBool('exp-nan', Exp(nan) <> Exp(nan));
  SayBool('exp-overflow-inf', Exp(800.0) > 1.0e308);
  SayBool('exp-underflow-zero', Exp(-800.0) = 0.0);
  { the denormal floor: exp(-745) is representable ONLY as a subnormal, so a
    flush-to-zero would show up right here }
  SayBool('exp-denormal-not-flushed', (Exp(-745.0) > 0.0) and (Exp(-745.0) < 1.0e-322));
  SayBool('ln-denormal-arg', (Ln(5.0e-324) < -744.0) and (Ln(5.0e-324) > -745.0));

  { Tanh saturates to EXACTLY +-1 and must never produce NaN: the old
    (e^x - e^-x)/(e^x + e^-x) was Inf/Inf for |x| >= 710. }
  SayBool('tanh-inf-one', Tanh(inf) = 1.0);
  SayBool('tanh-neginf-minus-one', Tanh(-inf) = -1.0);
  SayBool('tanh-800-one', Tanh(800.0) = 1.0);
  SayBool('tanh-neg800', Tanh(-800.0) = -1.0);
  SayBool('sinh-inf', Sinh(inf) > 1.0e308);
  SayBool('sinh-neginf', Sinh(-inf) < -1.0e308);
  SayBool('cosh-inf', Cosh(inf) > 1.0e308);
  SayBool('cosh-neginf-positive', Cosh(-inf) > 1.0e308);
  { a DOMAIN ERROR must be NaN, not 0.0 — a caller cannot tell 0.0 from
    ArcCosh(1.0), which legitimately IS 0.0 }
  SayBool('acosh-below-one-nan', ArcCosh(0.5) <> ArcCosh(0.5));
  SayBool('acosh-one-zero', ArcCosh(1.0) = 0.0);
  SayBool('atanh-above-one-nan', ArcTanh(1.5) <> ArcTanh(1.5));
  SayBool('atanh-one-inf', ArcTanh(1.0) > 1.0e308);
  SayBool('atanh-neg-one-neginf', ArcTanh(-1.0) < -1.0e308);
  SayBool('asinh-inf', ArcSinh(inf) > 1.0e308);

  { bounded, not growing: |sin| <= 1 must hold at every magnitude, which is the
    cheap check that catches a reduction that has come apart }
  SayBool('sin-bounded-1e10',  Abs(Sin(1.0e10))  <= 1.0);
  SayBool('sin-bounded-1e100', Abs(Sin(1.0e100)) <= 1.0);
  SayBool('sin-bounded-1e300', Abs(Sin(1.0e300)) <= 1.0);
  SayBool('cos-bounded-1e300', Abs(Cos(1.0e300)) <= 1.0);
  SayBool('pythagoras-1e10',
          Abs(Sin(1.0e10) * Sin(1.0e10) + Cos(1.0e10) * Cos(1.0e10) - 1.0) < 1.0e-15);
  SayBool('pythagoras-1e100',
          Abs(Sin(1.0e100) * Sin(1.0e100) + Cos(1.0e100) * Cos(1.0e100) - 1.0) < 1.0e-15);

  if failures = 0 then writeln('MATHFAST OK')
  else writeln('MATHFAST ', failures, ' FAILURES');
end.
