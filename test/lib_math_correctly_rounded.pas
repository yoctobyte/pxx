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
  x: Double;
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

  if failures = 0 then writeln('MATHROUND OK')
  else writeln('MATHROUND ', failures, ' FAILURES');
end.
