{ Ln / Log10 / Log2 / Exp / Power are CORRECTLY ROUNDED, asserted on the BITS.

  lib/rtl/math.pas used to be a plain-double atanh/Taylor series that landed
  ~1 ulp off on essentially every value, and needed a SnapLog special case to
  hit exact powers at all. It now runs on a double-double kernel ported from
  lib/crtl/src/math.c, which already had one — two mechanisms for one concept,
  and the port deleted the worse one
  (feature-rtl-ln-exp-are-a-ulp-off-port-the-crtl-dd-core).

  Asserted on the bit pattern, not on printed digits: `writeln(x:0:17)` goes
  through our own float formatter, so a digit comparison measures the formatter
  as much as the function. Every value below was verified two ways — against
  glibc via CPython, and against 60-digit Decimal arithmetic.

  THE LOG10 CASES AT THE END ARE THE INTERESTING ONES. They are values where we
  DISAGREE with glibc by one ulp, and 60-digit arithmetic says glibc is the one
  that is wrong: across a 1300-value random sweep, Ln and Log2 matched glibc
  bit-for-bit 1300/1300, while Log10 differed on 72 — and in all 72 pxx was the
  correctly rounded answer. glibc's log10 is not a correctly-rounded routine;
  its log, log2, exp and pow are. So for log10 the oracle has to be arbitrary
  precision, and "matches CPython" would be the WRONG assertion to write here. }
program lib_math_correctly_rounded;

uses math, sysutils;

type
  PI64 = ^Int64;

var
  failures: Integer;

function Bits(x: Double): string;
begin
  Result := IntToHex(PI64(@x)^, 16);
end;

procedure CheckBits(got: Double; const want, what: string);
begin
  if Bits(got) <> want then
  begin
    writeln('FAIL: ', what, ' got ', Bits(got), ' want ', want);
    failures := failures + 1;
  end;
end;

var
  x, y2: Double;
begin
  failures := 0;

  { ---- Ln: bit-identical to glibc on all 1300 sweep values ---- }
  x := 2.0;                CheckBits(Ln(x), '3FE62E42FEFA39EF', 'Ln(2)');
  x := 3.0;                CheckBits(Ln(x), '3FF193EA7AAD030B', 'Ln(3)');
  x := 7.0;                CheckBits(Ln(x), '3FFF2272AE325A57', 'Ln(7)');
  x := 10.0;               CheckBits(Ln(x), '40026BB1BBB55516', 'Ln(10)');
  x := 0.3;                CheckBits(Ln(x), 'BFF34378FCBDA721', 'Ln(0.3)');
  x := 1e300;              CheckBits(Ln(x), '4085963447F87FB5', 'Ln(1e300)');
  x := 1e-300;             CheckBits(Ln(x), 'C085963447F87FB5', 'Ln(1e-300)');
  x := 1.0000001;          CheckBits(Ln(x), '3E7AD7F2847B6492', 'Ln(1.0000001)');
  x := 123456.789;         CheckBits(Ln(x), '40277281CAD8A844', 'Ln(123456.789)');
  x := 2.718281828459045;  CheckBits(Ln(x), '3FF0000000000000', 'Ln(e) = exactly 1');

  { ---- Exp ---- }
  x := 1.0;    CheckBits(Exp(x), '4005BF0A8B145769', 'Exp(1)');
  x := 0.0;    CheckBits(Exp(x), '3FF0000000000000', 'Exp(0) = exactly 1');
  x := -1.0;   CheckBits(Exp(x), '3FD78B56362CEF38', 'Exp(-1)');
  x := 2.5;    CheckBits(Exp(x), '40285D6FD931E0BB', 'Exp(2.5)');
  x := 10.0;   CheckBits(Exp(x), '40D5829DCF950560', 'Exp(10)');
  x := -10.0;  CheckBits(Exp(x), '3F07CD79B5647C9B', 'Exp(-10)');
  x := 700.0;  CheckBits(Exp(x), '7F0D945DF4F8EC8E', 'Exp(700) — near overflow');
  x := -745.0; CheckBits(Exp(x), '0000000000000001', 'Exp(-745) — the smallest SUBNORMAL');
  x := 0.1;    CheckBits(Exp(x), '3FF1AEC7B35A00D4', 'Exp(0.1)');

  { ---- Power: was Exp(y*Ln(x)) in plain doubles, three roundings ---- }
  x := 2.0;  CheckBits(Power(x, 10.0), '4090000000000000', 'Power(2,10) = exactly 1024');
  x := 3.0;  CheckBits(Power(x, 7.0), '40A1160000000000', 'Power(3,7) = exactly 2187');
  x := 2.0;  CheckBits(Power(x, 0.5), '3FF6A09E667F3BCD', 'Power(2,0.5)');
  x := 1.5;  CheckBits(Power(x, 2.5), '40060B9FD68A4554', 'Power(1.5,2.5)');

  { ---- Power's IEEE edges. The old version answered 0.0 for EVERY base <= 0,
         which is wrong for each of these. ---- }
  x := -2.0;  CheckBits(Power(x, 3.0), 'C020000000000000', 'Power(-2,3) = -8');
  x := -2.0;  CheckBits(Power(x, 2.0), '4010000000000000', 'Power(-2,2) = 4');
  x := 0.0;   CheckBits(Power(x, 0.0), '3FF0000000000000', 'Power(0,0) = 1');
  x := -3.0;  CheckBits(Power(x, 0.0), '3FF0000000000000', 'Power(-3,0) = 1');
  x := 0.0;   CheckBits(Power(x, 3.0), '0000000000000000', 'Power(0,3) = 0');
  x := -2.0;
  if not IsNan(Power(x, 0.5)) then
  begin
    writeln('FAIL: Power(-2, 0.5) must be NaN (domain error), not 0');
    failures := failures + 1;
  end;

  { ---- Log2 and Log10 on exact powers: structural now, not snapped ---- }
  x := 8.0;    CheckBits(Log2(x), '4008000000000000', 'Log2(8) = exactly 3');
  x := 1024.0; CheckBits(Log2(x), '4024000000000000', 'Log2(1024) = exactly 10');
  x := 1000.0; CheckBits(Log10(x), '4008000000000000', 'Log10(1000) = exactly 3');
  x := 1e22;   CheckBits(Log10(x), '4036000000000000', 'Log10(1e22) = exactly 22');
  x := 3.0;    CheckBits(Log2(x), '3FF95C01A39FBD68', 'Log2(3)');

  { ---- Log10 where glibc is the one that is WRONG. Each verified against
         60-digit Decimal: ours is the correctly rounded double, glibc's is one
         ulp away. Do NOT "fix" these to match CPython. ---- }
  x := 8.7109639703653612e+29;
  CheckBits(Log10(x), '403DF0A82DFC023B', 'Log10(8.71e29) — glibc says ...3A');
  x := 8.5211835801175784e+29;
  CheckBits(Log10(x), '403DEE353E2D3533', 'Log10(8.52e29) — glibc says ...32');
  x := 1.0496153906095552e+29;
  CheckBits(Log10(x), '403D05623C0B0C6F', 'Log10(1.05e29) — glibc says ...70');
  x := 1.4948379613733309e+29;
  CheckBits(Log10(x), '403D2CB2333BCF13', 'Log10(1.49e29) — glibc says ...12');
  x := 4.2024017026064543e+29;
  CheckBits(Log10(x), '403D9F9D894D70F7', 'Log10(4.20e29) — glibc says ...F8');
  x := 0.022937365731945825;
  CheckBits(Log10(x), 'BFFA3B36B29925FE', 'Log10(0.0229) — glibc says ...FD');

  { ---- ArcSin / ArcCos / ArcTan, and Sqrt's rounding ----

    Added 2026-08-15 with the double-double port of the inverse trig
    ([[bug-b-arcsin-arccos-lose-2-ulps-vs-libm]]) and the neighbour-decision
    step in Sqrt ([[bug-b-sqrt-is-1-ulp-low-on-some-normal-inputs]]).

    Before: ArcSin disagreed with libm on 1977 of 3009 random arguments (max
    8 ulp), ArcCos on 1263 (max **1099** ulp, from `pi/2 - ArcSin` cancelling
    near x=1), and ArcTan — which the ticket recorded as "agrees exactly" from
    a single sample — on 2065 of 3005 (max 4 ulp). After: 0, 0 and 0 against a
    reference, and correctly rounded on 3000/3000.

    THE FIRST SEVEN ROWS ARE THE INTERESTING ONES, and they are the Log10
    situation again: we DISAGREE with glibc and 80-digit arithmetic says glibc
    is the one that is wrong. Its asin/acos are not correctly-rounded routines.
    The reference was validated the only way that means anything — it agrees
    with glibc on 200/200 fresh values, and then sides with us on these. Do NOT
    "fix" them to match CPython. ---- }
  x := 0.8944101310611605;
  CheckBits(ArcSin(x), '3FF1B6B993414C71', 'ArcSin(0.894410131) — glibc says ...72');
  x := -0.0953323100162855;
  CheckBits(ArcSin(x), 'BFB871335C006CFD', 'ArcSin(-0.09533231) — glibc says ...FC');
  x := 0.023212272044929705;
  CheckBits(ArcSin(x), '3F97C581214D681E', 'ArcSin(0.023212272) — glibc says ...1D');
  x := -0.3781660999438825;
  CheckBits(ArcSin(x), 'BFD8D1F3D1530305', 'ArcSin(-0.37816610) — glibc says ...04');
  x := 0.16096102228000353;
  CheckBits(ArcSin(x), '3FC4B16A65310D8B', 'ArcSin(0.160961022) — glibc says ...8A');
  x := 0.2058044565116668;
  CheckBits(ArcSin(x), '3FCA885666A35197', 'ArcSin(0.205804457) — glibc says ...96');
  x := 0.9063776739144427;
  CheckBits(ArcCos(x), '3FDBEA28A544ED43', 'ArcCos(0.906377674) — glibc says ...44');

  { ordinary arguments, where every source agrees }
  x := 0.5;
  CheckBits(ArcSin(x), '3FE0C152382D7366', 'ArcSin(0.5)');
  CheckBits(ArcCos(x), '3FF0C152382D7366', 'ArcCos(0.5)');
  x := -0.5;
  CheckBits(ArcSin(x), 'BFE0C152382D7366', 'ArcSin(-0.5)');
  CheckBits(ArcCos(x), '4000C152382D7366', 'ArcCos(-0.5)');
  x := 0.25;
  CheckBits(ArcSin(x), '3FD02BE9CE0B87CD', 'ArcSin(0.25)');
  CheckBits(ArcCos(x), '3FF51700E0C14B25', 'ArcCos(0.25)');
  x := 0.75;
  CheckBits(ArcSin(x), '3FEB235315C680DC', 'ArcSin(0.75)');
  CheckBits(ArcCos(x), '3FE720A392C1D955', 'ArcCos(0.75)');
  { near the endpoint, where 1-x*x cancels and the old form lost most of its
    bits, and where ArcCos as pi/2-ArcSin was 1099 ulp out }
  x := 0.9999;
  CheckBits(ArcSin(x), '3FF8E80E1A01556A', 'ArcSin(0.9999)');
  CheckBits(ArcCos(x), '3F8CF69D216BD74B', 'ArcCos(0.9999) — the 1099-ulp case');
  x := 1e-08;
  CheckBits(ArcSin(x), '3E45798EE2308C3A', 'ArcSin(1e-8)');
  CheckBits(ArcCos(x), '3FF921FB5194FB3C', 'ArcCos(1e-8)');

  x := 2.0;
  CheckBits(ArcTan(x), '3FF1B6E192EBBE44', 'ArcTan(2.0)');
  x := -2.0;
  CheckBits(ArcTan(x), 'BFF1B6E192EBBE44', 'ArcTan(-2.0)');
  x := 1.0e10;
  CheckBits(ArcTan(x), '3FF921FB543D4DE0', 'ArcTan(1e10)');
  x := 0.1;
  CheckBits(ArcTan(x), '3FB983E282E2CC4D', 'ArcTan(0.1)');

  { Sqrt — libm's sqrt IS correctly rounded (IEEE requires it), so here glibc
    is the oracle and these are the values where we used to be 1 ulp low.
    The last two are the range ENDS, where the exact-residual trick needs an
    exact power-of-two rescaling in each direction: near DBL_MAX the Dekker
    split's gh*gh overflows, and near the smallest normals its gl*gl flushes to
    zero. Both made the answer wrong for a reason that has nothing to do with
    the input being special. }
  x := 2.215827865120445e276;
  CheckBits(Sqrt(x), '5C9FFFFFFFFFFFFF', 'Sqrt(2.2158278651e276)');
  x := 2.2158278651204453e276;
  CheckBits(Sqrt(x), '5CA0000000000000', 'Sqrt(2.2158278651e276) neighbour');
  x := 1.7976931348623157e308;
  CheckBits(Sqrt(x), '5FEFFFFFFFFFFFFF', 'Sqrt(DBL_MAX)');
  x := 2.0383608471235588e-307;
  CheckBits(Sqrt(x), '201836AA9FA270DF', 'Sqrt(2.04e-307) — gl*gl underflow end');
  x := 3.0167274975908737e-308;
  CheckBits(Sqrt(x), '2002A14FFB5B7DAB', 'Sqrt(3.02e-308)');
  x := 5e-324;
  CheckBits(Sqrt(x), '1E60000000000000', 'Sqrt(smallest subnormal)');
  x := 2.0;
  CheckBits(Sqrt(x), '3FF6A09E667F3BCD', 'Sqrt(2)');

  { The PORTABLE path, asserted on the same values. On x86-64 `Sqrt` is one
    `sqrtsd`, so without these rows the software implementation every other
    target runs would never execute on the machine the gate runs on — it would
    only be reachable through the cross sweep, which is not where a broken
    residual should first show up. }
  x := 2.215827865120445e276;
  CheckBits(SqrtSoft(x), '5C9FFFFFFFFFFFFF', 'SqrtSoft(2.2158278651e276)');
  x := 2.2158278651204453e276;
  CheckBits(SqrtSoft(x), '5CA0000000000000', 'SqrtSoft(...) neighbour');
  x := 1.7976931348623157e308;
  CheckBits(SqrtSoft(x), '5FEFFFFFFFFFFFFF', 'SqrtSoft(DBL_MAX) — gh*gh overflow end');
  x := 2.0383608471235588e-307;
  CheckBits(SqrtSoft(x), '201836AA9FA270DF', 'SqrtSoft(2.04e-307) — gl*gl underflow end');
  x := 3.0167274975908737e-308;
  CheckBits(SqrtSoft(x), '2002A14FFB5B7DAB', 'SqrtSoft(3.02e-308)');
  x := 5e-324;
  CheckBits(SqrtSoft(x), '1E60000000000000', 'SqrtSoft(smallest subnormal)');
  x := 2.0;
  CheckBits(SqrtSoft(x), '3FF6A09E667F3BCD', 'SqrtSoft(2)');
  x := 1.0;
  CheckBits(SqrtSoft(x), '3FF0000000000000', 'SqrtSoft(1) — perfect square, no neighbour step');

  { ---- Sin / Cos / Tan: ARGUMENT REDUCTION ----

    Added 2026-08-15 with the double-double reduction port
    ([[bug-b-rtl-math-transcendentals-lose-argument-reduction]]). The old
    reduction was `x - Trunc(x/2pi)*2pi` in plain double with a rounded 2pi,
    and the error grew with the argument until nothing was left:

        x        sin ulp        cos ulp
        100           85             51
        1e6    1,220,648        228,032
        1e10   2,461,005,116  687,050,531

    At 1e10 the answer was uncorrelated with the true value. Two defects in one
    line: the rounded 2pi, and `Trunc(...)` into a 32-bit INTEGER, which
    overflows past x ~ 1.3e10.

    These rows are therefore not last-bit assertions — they are "does the
    reduction exist". 1e100 exercises the Payne-Hanek path (|x| >= 1e8) rather
    than Cody-Waite. Values are glibc's, verified against 400-digit arithmetic;
    where the two disagree — as they do for a huge argument near a multiple of
    pi/2 — the high-precision answer is the one written here. ---- }
  x := 100.0;
  CheckBits(Sin(x), 'BFE03425B78C4DB8', 'Sin(100) — was 85 ulp out');
  CheckBits(Cos(x), '3FEB981DBF665FDF', 'Cos(100) — was 51 ulp out');
  x := 123.456;
  CheckBits(Sin(x), 'BFE9B9DADC41AEB6', 'Sin(123.456)');
  CheckBits(Cos(x), 'BFE307E5980A1558', 'Cos(123.456)');
  CheckBits(Tan(x), '3FF5A0FE5DA94891', 'Tan(123.456)');
  x := 1000.0;
  CheckBits(Sin(x), '3FEA75CC150A206B', 'Sin(1000)');
  CheckBits(Cos(x), '3FE1FF026793F1BB', 'Cos(1000)');
  x := 1.0e6;
  CheckBits(Sin(x), 'BFD6664B2568D867', 'Sin(1e6) — was 1.2 MILLION ulp out');
  CheckBits(Cos(x), '3FEDF9DF9906D32C', 'Cos(1e6) — was 228,032 ulp out');
  x := 1.0e10;
  CheckBits(Sin(x), 'BFDF334C7896A4E3', 'Sin(1e10) — was 2.4 BILLION ulp out');
  CheckBits(Cos(x), '3FEBF098901C931A', 'Cos(1e10) — was 687 MILLION ulp out');
  CheckBits(Tan(x), 'BFE1DE000F443F50', 'Tan(1e10)');
  x := 1.0e100;
  CheckBits(Sin(x), 'BFD85C5E5B929359', 'Sin(1e100) — Payne-Hanek path');
  CheckBits(Cos(x), '3FED9757496841F5', 'Cos(1e100) — Payne-Hanek path');

  { ---- ArcTan2 ----

    Was 1 ulp off glibc on 1409 of 6000 random pairs while ArcTan itself was
    exact, because `ArcTan(y / x)` rounds the quotient before the function even
    starts. It now forms y/x as a double-double with the residual kept: 6 of
    6000 differ, and on all six the 400-digit answer is OURS
    ([[bug-b-rtl-math-transcendentals-lose-argument-reduction]]).

    The first three rows are those glibc-is-wrong cases. Do NOT "fix" them. }
  x := 18.854288599924047; y2 := 81.83644167225995;
  CheckBits(ArcTan2(x, y2), '3FCCFBF11D6E1B42', 'ArcTan2(18.85, 81.84) — glibc says ...41');
  x := -6.727848743085403; y2 := 73.10953505904877;
  CheckBits(ArcTan2(x, y2), 'BFB77DF63B37C795', 'ArcTan2(-6.73, 73.11) — glibc says ...94');
  x := 0.24908191119032774; y2 := 0.47061313011820993;
  CheckBits(ArcTan2(x, y2), '3FDF278E69FA39E7', 'ArcTan2(0.249, 0.471) — glibc says ...E6');

  x := 0.5; y2 := 1.0;
  CheckBits(ArcTan2(x, y2), '3FDDAC670561BB4F', 'ArcTan2(0.5, 1) — the value NilPy cited to stay away');
  x := -3.0; y2 := 4.0;
  CheckBits(ArcTan2(x, y2), 'BFE4978FA3269EE1', 'ArcTan2(-3, 4)');
  x := 1.0; y2 := -1.0;
  CheckBits(ArcTan2(x, y2), '4002D97C7F3321D2', 'ArcTan2(1, -1) — second quadrant');
  x := -1.0; y2 := -1.0;
  CheckBits(ArcTan2(x, y2), 'C002D97C7F3321D2', 'ArcTan2(-1, -1) — third quadrant');

  { SIGNED ZEROS. atan2 propagates them, and `-0.0 < 0.0` is False, so the
    old sign test answered +pi where -pi is required. FPC 3.2.2 and CPython
    agree bit for bit on all of these. }
  x := 0.0; y2 := -1.0;
  CheckBits(ArcTan2(x, y2), '400921FB54442D18', 'ArcTan2(+0, -1) = +pi');
  x := -0.0; y2 := -1.0;
  CheckBits(ArcTan2(x, y2), 'C00921FB54442D18', 'ArcTan2(-0, -1) = -pi');
  x := -0.0; y2 := 1.0;
  CheckBits(ArcTan2(x, y2), '8000000000000000', 'ArcTan2(-0, 1) = -0');
  x := -0.0; y2 := 0.0;
  CheckBits(ArcTan2(x, y2), '8000000000000000', 'ArcTan2(-0, +0) = -0');

  if failures = 0 then writeln('MATHROUND OK')
  else writeln('MATHROUND ', failures, ' FAILURES');
end.
