{ SPDX-License-Identifier: Zlib }
unit math;
interface
uses math_ext;

function Abs(x: Integer): Integer;
function Abs(x: Int64): Int64;
function Min(a, b: Integer): Integer;
function Max(a, b: Integer): Integer;
function Power(base, exponent: Integer): Integer;
function Gcd(a, b: Integer): Integer;
function Lcm(a, b: Integer): Integer;

{ Floating-point math — pure Pascal, no libm (keeps the no-libc design), native
  x86-64; other-CPU asm optimizations come later. Extended is NOT supported here
  (it is currently aliased to Double); only Single + Double overloads.

  Conventions / known compiler quirks honoured below:
  - All numeric constants are float literals (`0.0`, `2.0`, `10.0`): a plain int
    literal into a Double can miss the int->float conversion, so we spell them out.
  - Never read-modify a function Result inside a loop (it can miscompile to 0,
    feature-result-in-loop); accumulate in a local and assign Result at the end.
  - `Trunc`, `Round`, `Frac`, `Int` are compiler builtins (not redefined here).
  - Single overloads are thin wrappers: widen to Double, compute, narrow back. }

{ ---- Double core ---- }
function Pi: Double;
function Abs(x: Double): Double;
function Sqrt(x: Double): Double;
function Exp(x: Double): Double;
function Ln(x: Double): Double;
function Sin(x: Double): Double;
function Cos(x: Double): Double;
function Tan(x: Double): Double;
function ArcSin(x: Double): Double;
function ArcCos(x: Double): Double;
function ArcTan(x: Double): Double;
function ArcTan2(y, x: Double): Double;
function Sinh(x: Double): Double;
function Cosh(x: Double): Double;
function Tanh(x: Double): Double;
function ArcSinh(x: Double): Double;
function ArcCosh(x: Double): Double;
function ArcTanh(x: Double): Double;
function Cot(x: Double): Double;
function Sec(x: Double): Double;
function Csc(x: Double): Double;
function Log10(x: Double): Double;
function Log2(x: Double): Double;
function LogN(base, x: Double): Double;
function Hypot(x, y: Double): Double;
function Power(base, exponent: Double): Double;
function IntPower(base: Double; n: Integer): Double;
{ FPC's Floor/Ceil return INTEGER (Floor64/Ceil64 give Int64) — they are not
  C's floor()/ceil(). They used to return Double here, which is C semantics
  wearing FPC's names, and the divergence had already propagated into our own
  tree: examples/raytracer wrote `Trunc(Floor(p.x))`, a wrapper that exists
  ONLY because Floor handed back a float. In FPC that is plain `Floor(p.x)`.
  bug-b-fpc-numeric-compat-floor-ceil-return-float-currency-is-double.

  The Integer forms overflow past 2^31 exactly as FPC's do — that is why FPC
  ships the 64-bit pair, and why RTL code that floors a large magnitude must
  reach for Floor64. }
function Floor(x: Double): Integer;
function Ceil(x: Double): Integer;
function Floor64(x: Double): Int64;
function Ceil64(x: Double): Int64;
function FMod(x, y: Double): Double;
function Sign(x: Double): Integer;
function Min(a, b: Double): Double;
function Max(a, b: Double): Double;
function DegToRad(d: Double): Double;
function RadToDeg(r: Double): Double;

{ ---- FPC's RoundTo family ----
  Both formulas are FPC's OWN, read off rtl/objpas/math.pp rather than derived,
  because the obvious derivation gives different answers:

    RoundTo:        RV := IntPower(10, digits);  Round(value / RV) * RV
    SimpleRoundTo:  RV := IntPower(10, -digits); Int(value*RV +/- 0.5) / RV

  RoundTo DIVIDES by 10^digits where the natural reading is to multiply by
  10^-digits, and that is not cosmetic: 2.675 / 0.01 is 267.50000000000006 while
  2.675 * 100 is 267.49999999999997, so the first rounds to 2.68 and the second
  to 2.67. FPC prints 2.68. Measured, not reasoned.

  The two differ only in the tie rule — RoundTo inherits Round's nearest-even,
  SimpleRoundTo is half-away-from-zero — which is exactly why FPC ships both,
  and why `SimpleRoundTo(0.125, -2)` is 0.13 where `RoundTo(0.125, -2)` is 0.12.

  NO Extended overloads: Extended is aliased to Double here and this RTL targets
  Single + Double only (feature-extended-type-support). }
type
  TRoundToRange = -37..37;

function RoundTo(const AValue: Double; const Digits: TRoundToRange): Double;
function SimpleRoundTo(const AValue: Double; const Digits: TRoundToRange): Double;
function RoundTo(const AValue: Single; const Digits: TRoundToRange): Single;
function SimpleRoundTo(const AValue: Single; const Digits: TRoundToRange): Single;

{ ---- Python `math` module surface ----
  NilPy's `import math` resolves ordinary names straight against THIS unit,
  case-insensitively, so a Python spelling with no Pascal counterpart under that
  name simply does not exist (feature-rtl-math-surface-gaps measured 16).

  FOUR NAMES ARE DELIBERATELY ABSENT — `pow`, `log`, `copysign` and `atan2` —
  and adding them is a trap that measures as a C REGRESSION rather than a Pascal
  one:
  `pxxcio` is auto-pulled into every C program and does `uses math`, so every
  name here is in scope for C name resolution and a Pascal `Pow`/`Log`/
  `CopySign` HIJACKS libc's. Measured: gcc gives pow(2,10) = 1024, and with a
  `Pow` in this unit a C program answered 1; `copysign(3,-1)` answered 0.785398,
  which is atan2's result. `Atan2` was added anyway and DID ship broken for one
  commit — test/cmath_trig_family_b385.c went red with atan2(0.5,1) answering
  atan(1) — because the first canary only checked atan2(1,1), whose arguments
  are symmetric, so a swapped or ignored argument is invisible in it. The canary
  uses asymmetric arguments now. Filed as
  bug-c-pascal-math-names-hijack-libc-through-pxxcio; NilPy gets intercepts for
  those three instead. `trunc` is absent for a different reason — Python's
  returns an int, the same contract mismatch that made math.floor/ceil
  intercepts.

  IsClose uses Python's defaults: rel_tol 1e-09, abs_tol 0.0; equal infinities
  are close and NaN never is. }
function E: Double;
function Tau: Double;
function Inf: Double;
function NaN: Double;
function IsNan(x: Double): Boolean;
function IsInf(x: Double): Boolean;
function Degrees(r: Double): Double;
function Radians(d: Double): Double;
function IsClose(a, b: Double): Boolean;
function IsClose(a, b, relTol, absTol: Double): Boolean;
function Factorial(n: Integer): Int64;
function Comb(n, k: Integer): Int64;

{ ---- Single overloads (widen -> Double -> narrow) ---- }
function Abs(x: Single): Single;
function Sqrt(x: Single): Single;
function Exp(x: Single): Single;
function Ln(x: Single): Single;
function Sin(x: Single): Single;
function Cos(x: Single): Single;
function Tan(x: Single): Single;
function ArcSin(x: Single): Single;
function ArcCos(x: Single): Single;
function ArcTan(x: Single): Single;
function Sinh(x: Single): Single;
function Cosh(x: Single): Single;
function Tanh(x: Single): Single;
function Log10(x: Single): Single;
function Log2(x: Single): Single;
function Hypot(x, y: Single): Single;
function Power(base, exponent: Single): Single;
function Floor(x: Single): Integer;
function Ceil(x: Single): Integer;

implementation

type
  PSqrtInt64  = ^Int64;    { double<->bits reinterpret for the Sqrt seed }
  PSqrtDouble = ^Double;

{ ================= Double core ================= }

function Pi: Double;
begin
  Result := 3.14159265358979323846;
end;

function Abs(x: Double): Double;
begin
  if x < 0.0 then Result := -x else Result := x;
end;

function Sqrt(x: Double): Double;
{ Newton-Raphson to ~1 ULP, then ONE correctly-rounded correction step using an
  exact residual. Plain Newton has an FP fixed point that can sit 1 ULP below the
  correctly-rounded root (sqrt(2) landed at ...bcc vs the IEEE ...bcd), and every
  RTL routine built on Sqrt inherited that error. The correction computes the
  exact residual r = x - g*g with a Dekker two-product (no FMA needed), then
  applies r/(2g): sqrt(x) = g*sqrt(1+r/g^2) ~= g + r/(2g) to well past double
  precision, so rounding g + r/(2g) yields the correctly-rounded result. }
var g, ng, z, gh, gl, c, p, e, r: Double; i: Integer; bits: Int64;
begin
  { FPC-faithful IEEE: Sqrt of a negative is NaN (C sqrt() binds here and expects
    NaN too). Sqrt(0)=0. z/z with z=0 yields a NaN without a NaN literal. }
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
  if x = 0.0 then begin Result := 0.0; Exit; end;
  { Bit-hack seed: halving the raw exponent field gives g within a small factor
    of sqrt(x) for ANY magnitude, so Newton converges quadratically in a handful
    of steps. (`g := x` seeded far from the root for large/small x, needing far
    more than the old 200-iteration cap — huge inputs never converged.)
    (bits shr 1) + (1023 shl 51) re-biases the halved exponent. }
  bits := PSqrtInt64(@x)^;
  bits := (bits shr 1) + (Int64(1023) shl 51);
  g := PSqrtDouble(@bits)^;
  for i := 1 to 8 do
  begin
    ng := 0.5 * (g + x / g);
    if ng = g then break;
    g := ng;
  end;
  { Dekker split of g into gh+gl (hi 26 bits + lo), so gh*gh, gh*gl, gl*gl are
    each exact; then g*g = p (rounded) + e (exact error), and the exact residual
    is (x - p) - e. 134217729 = 2^27 + 1. }
  p := g * g;
  { Near DBL_MAX, g*g overflows to +Inf and the residual would be NaN; the
    Newton result is already ~1 ULP there, so skip the correction. (p - p = 0
    for a finite p, NaN for Inf.) }
  if (p - p) <> 0.0 then
  begin
    Result := g;
    Exit;
  end;
  c  := g * 134217729.0;
  gh := c - (c - g);
  gl := g - gh;
  e  := ((gh * gh - p) + 2.0 * gh * gl) + gl * gl;
  r  := (x - p) - e;
  Result := g + r / (2.0 * g);
end;

{ ================= double-double kernel =================

  lib/crtl/src/math.c has had a correctly-rounded log/exp core since the C
  runtime needed one; this unit had a plain-double atanh series that landed
  ~1 ulp off on every value and needed a SnapLog special case to hit exact
  powers at all (bug-rtl-log10-is-inexact-for-powers-of-ten). Two mechanisms
  for one concept, and this is the port that removes the worse one — same
  algorithm, same constants, in Pascal.

  A TDd carries hi + lo with |lo| <= ulp(hi)/2, so the pair holds ~106 bits.
  Every operation below is an error-free transformation: the rounding error of
  a double operation is computed exactly and kept in lo. Constants come from
  BIT PATTERNS rather than decimal literals so accuracy does not depend on the
  literal parser. }

type
  TDd = record
    Hi: Double;
    Lo: Double;
  end;

function DdBits(b: Int64): Double;
begin
  Result := PSqrtDouble(@b)^;
end;

{ |a| >= |b| assumed — one operation fewer than the general 2Sum. }
function DdFast2Sum(a, b: Double): TDd;
begin
  Result.Hi := a + b;
  Result.Lo := b - (Result.Hi - a);
end;

function Dd2Sum(a, b: Double): TDd;
var bb: Double;
begin
  Result.Hi := a + b;
  bb := Result.Hi - a;
  Result.Lo := (a - (Result.Hi - bb)) + (b - bb);
end;

{ Dekker two-product, no FMA. Exact while |a|,|b| < 2^995. }
function Dd2Prod(a, b: Double): TDd;
var sa, sb, ah, al, bh, bl: Double;
begin
  sa := 134217729.0 * a;        { 2^27 + 1 split }
  sb := 134217729.0 * b;
  ah := sa - (sa - a); al := a - ah;
  bh := sb - (sb - b); bl := b - bh;
  Result.Hi := a * b;
  Result.Lo := ((ah * bh - Result.Hi) + ah * bl + al * bh) + al * bl;
end;

function DdAdd(a, b: TDd): TDd;
var s: TDd;
begin
  s := Dd2Sum(a.Hi, b.Hi);
  s.Lo := s.Lo + a.Lo + b.Lo;
  Result := DdFast2Sum(s.Hi, s.Lo);
end;

function DdAddD(a: TDd; b: Double): TDd;
var s: TDd;
begin
  s := Dd2Sum(a.Hi, b);
  s.Lo := s.Lo + a.Lo;
  Result := DdFast2Sum(s.Hi, s.Lo);
end;

function DdMul(a, b: TDd): TDd;
var p: TDd;
begin
  p := Dd2Prod(a.Hi, b.Hi);
  p.Lo := p.Lo + a.Hi * b.Lo + a.Lo * b.Hi;
  Result := DdFast2Sum(p.Hi, p.Lo);
end;

function DdMulD(a: TDd; b: Double): TDd;
var p: TDd;
begin
  p := Dd2Prod(a.Hi, b);
  p.Lo := p.Lo + a.Lo * b;
  Result := DdFast2Sum(p.Hi, p.Lo);
end;

function DdDivD(a: TDd; b: Double): TDd;
var p: TDd; q1, q2: Double;
begin
  q1 := a.Hi / b;
  p := Dd2Prod(q1, b);
  q2 := ((a.Hi - p.Hi) - p.Lo + a.Lo) / b;
  Result := DdFast2Sum(q1, q2);
end;

function DdDiv(a, b: TDd): TDd;
var p, e, q: TDd; q1, q2, q3: Double;
begin
  q1 := a.Hi / b.Hi;
  p := DdMulD(b, q1);
  e := DdAdd(a, DdMulD(p, -1.0));
  q2 := e.Hi / b.Hi;
  p := DdMulD(b, q2);
  e := DdAdd(e, DdMulD(p, -1.0));
  q3 := e.Hi / b.Hi;
  q := DdFast2Sum(q1, q2);
  Result := DdAddD(q, q3);
end;

{ ln2 as a double-double: 0x1.62e42fefa39efp-1 and its tail. }
function DdLn2: TDd;
begin
  Result.Hi := DdBits($3FE62E42FEFA39EF);
  Result.Lo := DdBits($3C7ABC9E3B39803F);
end;

{ x * 2^e, exactly. Built from constructed powers of two rather than a loop:
  e reaches +-1074 on the subnormal paths, and 1074 iterations on the exp hot
  path is not acceptable. Stepped so no intermediate overflows or flushes on
  the way to a representable answer. }
function DdLdexp(x: Double; e: Integer): Double;
var r: Double;
begin
  r := x;
  while e > 1023 do
  begin
    r := r * DdBits($7FE0000000000000);   { 2^1023 }
    e := e - 1023;
  end;
  while e < -1022 do
  begin
    r := r * DdBits($0010000000000000);   { 2^-1022 }
    e := e + 1022;
  end;
  if e <> 0 then
    r := r * DdBits(Int64(e + 1023) shl 52);
  Result := r;
end;

{ Round half to EVEN — the IEEE default, and what C's rint does under it. }
function DdRint(x: Double): Double;
var t, f, a: Double;
begin
  a := Abs(x);
  if a >= 4503599627370496.0 then begin Result := x; Exit; end;  { >= 2^52: integral }
  { Int(), not Floor(): a is non-negative here so the two agree, and Floor now
    returns a 32-bit Integer which would SILENTLY OVERFLOW for a between 2^31
    and 2^52 — a range this function is explicitly still handling. }
  t := Int(a);
  f := a - t;
  if f > 0.5 then t := t + 1.0
  else if f = 0.5 then
  begin
    if t - 2.0 * Int(t / 2.0) <> 0.0 then t := t + 1.0;   { ties to even }
  end;
  if x < 0.0 then Result := -t else Result := t;
end;

{ log(x) as a double-double; x finite and > 0.
  Normalize x = 2^e * m with m in [sqrt2/2, sqrt2), so z = (m-1)/(m+1) has
  |z| <= 0.1716 and 18 odd terms reach ~2^-88; then add e*ln2 in dd. This is
  what makes the exact cases fall out STRUCTURALLY — log2(2^n) = n needs no
  snapping when e*ln2 is carried exactly and the series contributes zero. }
function DdLogD(x: Double): TDd;
var
  b, mb: Int64;
  e, i: Integer;
  xx, m: Double;
  md, z, z2, s, t, num, den: TDd;
begin
  xx := x;
  b := PSqrtInt64(@xx)^;
  if (b shr 52) = 0 then
  begin
    xx := xx * DdBits($4350000000000000);          { subnormal: through 2^54 }
    b := PSqrtInt64(@xx)^;
    e := Integer(b shr 52) - 1023 - 54;
  end
  else
    e := Integer(b shr 52) - 1023;
  mb := (b and $000FFFFFFFFFFFFF) or $3FF0000000000000;
  m := DdBits(mb);                                 { [1, 2) }
  if m > DdBits($3FF6A09E667F3BCD) then            { > sqrt2: halve }
  begin
    m := m * 0.5;
    e := e + 1;
  end;
  md.Hi := m;
  md.Lo := 0.0;
  { z = (m-1)/(m+1); m-1 is Sterbenz-exact, m+1 exact since m < 2 }
  num := DdAddD(md, -1.0);
  den := DdAddD(md, 1.0);
  z := DdDiv(num, den);
  z2 := DdMul(z, z);                               { z^2 <= 0.02944 }
  t.Hi := 1.0; t.Lo := 0.0;
  s := DdDivD(t, 37.0);
  for i := 17 downto 0 do                          { Horner over the odd terms }
  begin
    s := DdMul(s, z2);
    s := DdAdd(s, DdDivD(t, Double(2 * i + 1)));
  end;
  s := DdMul(DdMulD(z, 2.0), s);
  Result := DdAdd(DdMulD(DdLn2, Double(e)), s);
end;

{ Round a dd (|lo| <= ulp(hi)/2, hi roughly in [0.5, 3)) times 2^k to a double
  with ONE effective rounding, subnormal- and overflow-correct. For normal and
  overflow results fl(hi+lo) is already the correctly rounded 53-bit value and
  the power-of-two scale is exact. Subnormal results cannot go that way — the
  scale would round a second time — so they are rebuilt integrally: shift until
  the result's ulp is 1, round to an integer with ties-to-even using the EXACT
  dd residual, then scale back (n * 2^-1074 is exact). }
function DdScale(v: TDd; k: Integer): Double;
var
  d, r, ih, il, n0: Double;
  g: TDd;
  sh: Integer;
begin
  d := v.Hi + v.Lo;
  if d = 0.0 then begin Result := d; Exit; end;
  if k > 1100 then k := 1100;
  if k < -1140 then k := -1140;
  r := DdLdexp(d, k);
  if (r > 1.7976931348623157e308) or (r < -1.7976931348623157e308)
     or (Abs(r) >= DdBits($0010000000000000)) then    { Inf, or >= DBL_MIN }
  begin
    Result := r;
    Exit;
  end;
  sh := k + 1074;
  ih := DdLdexp(v.Hi, sh);                { exact }
  il := DdLdexp(v.Lo, sh);                { exact }
  n0 := DdRint(ih);
  g := Dd2Sum(ih - n0, il);               { ih-n0 is Sterbenz-exact }
  if (g.Hi > 0.5) or ((g.Hi = 0.5) and ((g.Lo > 0.0) or
       ((g.Lo = 0.0) and (FMod(n0, 2.0) <> 0.0)))) then
    n0 := n0 + 1.0
  else if (g.Hi < -0.5) or ((g.Hi = -0.5) and ((g.Lo < 0.0) or
       ((g.Lo = 0.0) and (FMod(n0, 2.0) <> 0.0)))) then
    n0 := n0 - 1.0;
  Result := DdLdexp(n0, -1074);           { exact subnormal rebuild }
end;

{ Shared exp reduction: a = k*ln2 + r with |r| <= ln2/2; returns e^r as a dd in
  [0.7, 1.42] by a 22-term Taylor (0.347^22/22! ~ 2^-98), and k through kOut. }
function DdExpCore(a: TDd; var kOut: Integer): TDd;
var kd: Double; i: Integer; r, sres, p, ln2: TDd;
begin
  ln2 := DdLn2;
  kd := DdRint(a.Hi * DdBits($3FF71547652B82FE));   { 1/ln2 }
  kOut := Trunc(kd);
  p := Dd2Prod(kd, ln2.Hi);                        { exact product }
  r := Dd2Sum(a.Hi, -p.Hi);
  r.Lo := r.Lo + ((-p.Lo - kd * ln2.Lo) + a.Lo);
  { FULL 2sum, not fast2sum: near x = k*ln2 the exact difference r.Hi can be
    SMALLER than the correction r.Lo, so fast2sum's |a| >= |b| precondition
    fails. }
  r := Dd2Sum(r.Hi, r.Lo);
  sres.Hi := 1.0; sres.Lo := 0.0;
  for i := 22 downto 1 do                          { Horner: s = 1 + (r/i)*s }
  begin
    sres := DdMul(DdDivD(r, Double(i)), sres);
    sres := DdAddD(sres, 1.0);
  end;
  Result := sres;
end;

function Exp(x: Double): Double;
{ Correctly rounded, over the double-double kernel: reduce x = k*ln2 + r with
  ln2 carried to ~106 bits, Taylor e^r, then one rounding on the way out. The
  old plain-double version was ~1 ulp off (exp(1) came back as
  2.7182818284590446 against libm's 2.718281828459045). }
var a, sres: TDd; k: Integer;
begin
  if x <> x then begin Result := x; Exit; end;                { NaN }
  if x > 710.0 then begin Result := DdLdexp(1.0, 1024) * 2.0; Exit; end;   { +Inf }
  if x < -746.0 then begin Result := DdBits(1) * 0.5; Exit; end;           { +0 }
  a.Hi := x;
  a.Lo := 0.0;
  sres := DdExpCore(a, k);
  Result := DdScale(sres, k);
end;

function Ln(x: Double): Double;
{ Correctly rounded, over the double-double kernel above. }
var z: Double; r: TDd;
begin
  { FPC-faithful IEEE: Ln(0) = -Inf, Ln(negative) = NaN (C log() binds here). }
  if x <> x then begin Result := x; Exit; end;
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
  if x = 0.0 then begin z := 0.0; Result := -1.0 / z; Exit; end;
  if x > 1.7976931348623157e308 then begin Result := x; Exit; end;   { +Inf }
  r := DdLogD(x);
  Result := r.Hi + r.Lo;
end;

function Sin(x: Double): Double;
{ reduce mod 2Pi to [-Pi,Pi], then Taylor. }
var r, term, sum, p: Double; k, i, den: Integer;
begin
  k := Trunc(x / 6.28318530717958647692);
  r := x - k * 6.28318530717958647692;
  if r > 3.14159265358979323846 then r := r - 6.28318530717958647692;
  if r < -3.14159265358979323846 then r := r + 6.28318530717958647692;
  term := r; sum := r; p := r * r; i := 1;
  while i <= 30 do
  begin
    den := (2 * i) * (2 * i + 1);
    term := -term * p / den;
    sum := sum + term;
    i := i + 1;
  end;
  Result := sum;
end;

function Cos(x: Double): Double;
var r, term, sum, p: Double; k, i, den: Integer;
begin
  k := Trunc(x / 6.28318530717958647692);
  r := x - k * 6.28318530717958647692;
  if r > 3.14159265358979323846 then r := r - 6.28318530717958647692;
  if r < -3.14159265358979323846 then r := r + 6.28318530717958647692;
  term := 1.0; sum := 1.0; p := r * r; i := 1;
  while i <= 30 do
  begin
    den := (2 * i - 1) * (2 * i);
    term := -term * p / den;
    sum := sum + term;
    i := i + 1;
  end;
  Result := sum;
end;

function Tan(x: Double): Double;
begin
  Result := Sin(x) / Cos(x);
end;

function ArcTan(x: Double): Double;
{ atan(r)=2*atan(r/(1+sqrt(1+r^2))) reduction until |r| small, then Taylor,
  then undo by doubling. Scaling in a LOCAL (never Result in a loop). }
var r, term, sum, p: Double; i, nred: Integer;
begin
  r := x;
  nred := 0;
  while (r > 0.3) or (r < -0.3) do
  begin
    r := r / (1.0 + Sqrt(1.0 + r * r));
    nred := nred + 1;
  end;
  p := r * r;
  term := r; sum := r; i := 3;
  while i <= 59 do
  begin
    term := -term * p;
    sum := sum + term / i;
    i := i + 2;
  end;
  i := nred;
  while i > 0 do begin sum := sum * 2.0; i := i - 1; end;
  Result := sum;
end;

function ArcSin(x: Double): Double;
begin
  if x >= 1.0 then begin Result := 1.57079632679489661923; Exit; end;
  if x <= -1.0 then begin Result := -1.57079632679489661923; Exit; end;
  Result := ArcTan(x / Sqrt(1.0 - x * x));
end;

function ArcCos(x: Double): Double;
begin
  Result := 1.57079632679489661923 - ArcSin(x);
end;

function ArcTan2(y, x: Double): Double;
begin
  if x > 0.0 then
    Result := ArcTan(y / x)
  else if x < 0.0 then
  begin
    if y >= 0.0 then Result := ArcTan(y / x) + 3.14159265358979323846
    else Result := ArcTan(y / x) - 3.14159265358979323846;
  end
  else
  begin
    if y > 0.0 then Result := 1.57079632679489661923
    else if y < 0.0 then Result := -1.57079632679489661923
    else Result := 0.0;
  end;
end;

function Sinh(x: Double): Double;
begin
  Result := 0.5 * (Exp(x) - Exp(-x));
end;

function Cosh(x: Double): Double;
begin
  Result := 0.5 * (Exp(x) + Exp(-x));
end;

function Tanh(x: Double): Double;
var ex, enx: Double;
begin
  ex := Exp(x);
  enx := Exp(-x);
  Result := (ex - enx) / (ex + enx);
end;

function ArcSinh(x: Double): Double;
begin
  Result := Ln(x + Sqrt(x * x + 1.0));
end;

function ArcCosh(x: Double): Double;
begin
  if x < 1.0 then begin Result := 0.0; Exit; end;
  Result := Ln(x + Sqrt(x * x - 1.0));
end;

function ArcTanh(x: Double): Double;
begin
  Result := 0.5 * Ln((1.0 + x) / (1.0 - x));
end;

function Cot(x: Double): Double;
begin
  Result := Cos(x) / Sin(x);
end;

function Sec(x: Double): Double;
begin
  Result := 1.0 / Cos(x);
end;

function Csc(x: Double): Double;
begin
  Result := 1.0 / Sin(x);
end;

{ Log10 / Log2 / LogN over the double-double log.

  SnapLog USED TO LIVE HERE: the old plain-double Ln landed a hair below the
  integer for exact powers, so Log10(1000) was 2.9999999999999996 and
  Trunc(Log10(n)) + 1 — the digit-count idiom — was wrong for nearly every power
  of ten (bug-rtl-log10-is-inexact-for-powers-of-ten). It rounded the quotient
  and snapped when base^k reproduced x.

  It is gone because the dd core does not need it. The exact cases now fall out
  STRUCTURALLY: for x = base^k the series contributes zero and the answer is
  k*ln(base) carried to ~106 bits, divided by the same constant to the same
  precision. Deleting the special case rather than keeping it beside the fix is
  the point (devdocs/dev/normalise-dont-special-case.md).

  The multiply is by a DOUBLE-DOUBLE 1/ln10 resp. 1/ln2, not a plain division of
  the rounded log: dividing a correctly-rounded Ln by a rounded constant is a
  second rounding, and it measured as 1 ulp off libm on Log10(3), Log10(0.3) and
  Log2(7) while Ln itself was already bit-identical. }
function Log10(x: Double): Double;
var r, c: TDd; z: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
  if x = 0.0 then begin z := 0.0; Result := -1.0 / z; Exit; end;
  if x > 1.7976931348623157e308 then begin Result := x; Exit; end;
  c.Hi := DdBits($3FDBCB7B1526E50E);        { 1/ln10 }
  c.Lo := DdBits($3C695355BAAAFAD3);
  r := DdMul(DdLogD(x), c);
  Result := r.Hi + r.Lo;
end;

function Log2(x: Double): Double;
var r, c: TDd; z: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
  if x = 0.0 then begin z := 0.0; Result := -1.0 / z; Exit; end;
  if x > 1.7976931348623157e308 then begin Result := x; Exit; end;
  c.Hi := DdBits($3FF71547652B82FE);        { 1/ln2 }
  c.Lo := DdBits($3C7777D0FFDA0D24);
  r := DdMul(DdLogD(x), c);
  Result := r.Hi + r.Lo;
end;

function LogN(base, x: Double): Double;
{ NOTE the argument order — base FIRST, as in FPC. Python's math.log(x, base) is
  the other way round, which is why NilPy needs its own intercept rather than
  binding to this (bug-n-math-trunc-and-log-need-frontend-intercepts). }
var r: TDd; z: Double;
begin
  if (x <> x) or (base <> base) then begin Result := x + base; Exit; end;
  if (x <= 0.0) or (base <= 0.0) or (base = 1.0) then
  begin
    { same IEEE edges as Ln, computed rather than special-cased }
    Result := Ln(x) / Ln(base);
    Exit;
  end;
  r := DdDiv(DdLogD(x), DdLogD(base));
  Result := r.Hi + r.Lo;
end;

function Hypot(x, y: Double): Double;
begin
  Result := Sqrt(x * x + y * y);
end;

{ ---- FPC's RoundTo family (see the interface note for why these formulas) ---- }

function RoundTo(const AValue: Double; const Digits: TRoundToRange): Double;
var rv: Double;
begin
  rv := IntPower(10.0, Digits);
  Result := Round(AValue / rv) * rv;
end;

function SimpleRoundTo(const AValue: Double; const Digits: TRoundToRange): Double;
var rv: Double;
begin
  rv := IntPower(10.0, -Digits);
  if AValue < 0.0 then Result := Int((AValue * rv) - 0.5) / rv
  else Result := Int((AValue * rv) + 0.5) / rv;
end;

function RoundTo(const AValue: Single; const Digits: TRoundToRange): Single;
begin
  Result := RoundTo(Double(AValue), Digits);
end;

function SimpleRoundTo(const AValue: Single; const Digits: TRoundToRange): Single;
begin
  Result := SimpleRoundTo(Double(AValue), Digits);
end;

{ ---- Python `math` module surface (see the interface note) ---- }

function E: Double;
begin
  Result := 2.71828182845904523536;
end;

function Tau: Double;
begin
  Result := 6.28318530717958647692;
end;

{ Inf and NaN are built from the IEEE BIT PATTERNS, not 1.0/0.0 and 0.0/0.0.
  The division form is the obvious one and it is wrong twice over: NilPy raises
  ZeroDivisionError on the divide, so `math.inf` DIED rather than answering, and
  a checked-arithmetic build would trap for the same reason. The reinterpret is
  exact by construction anyway — the same trick as the Sqrt seed above. }
function Inf: Double;
var bits: Int64; p: PSqrtDouble;
begin
  bits := $7FF0000000000000;
  p := PSqrtDouble(@bits);
  Result := p^;
end;

function NaN: Double;
var bits: Int64; p: PSqrtDouble;
begin
  bits := $7FF8000000000000;    { quiet NaN }
  p := PSqrtDouble(@bits);
  Result := p^;
end;

function IsNan(x: Double): Boolean;
begin
  { The only value not equal to itself — and the reason this needs to exist is
    that `x <> x` is the trick everyone has to know without it. }
  Result := x <> x;
end;

function IsInf(x: Double): Boolean;
begin
  Result := (x > 1.7976931348623157e308) or (x < -1.7976931348623157e308);
end;

function Degrees(r: Double): Double;
begin
  Result := RadToDeg(r);
end;

function Radians(d: Double): Double;
begin
  Result := DegToRad(d);
end;

function IsClose(a, b, relTol, absTol: Double): Boolean;
var d, m, ta, tb: Double;
begin
  if (a <> a) or (b <> b) then begin Result := False; Exit; end;   { NaN }
  if a = b then begin Result := True; Exit; end;                   { incl. equal Inf }
  if IsInf(a) or IsInf(b) then begin Result := False; Exit; end;   { differing Inf }
  d := Abs(a - b);
  ta := Abs(a); tb := Abs(b);
  if ta > tb then m := ta else m := tb;
  Result := (d <= relTol * m) or (d <= absTol);
end;

function IsClose(a, b: Double): Boolean;
begin
  Result := IsClose(a, b, 1.0e-9, 0.0);   { Python's defaults }
end;

function Factorial(n: Integer): Int64;
var i: Integer; r: Int64;
begin
  { Python's factorial is arbitrary precision; Int64 holds it exactly to 20! and
    overflows past that, so the range is the honest limit of the return type
    rather than a choice made here. }
  r := 1;
  for i := 2 to n do r := r * i;
  if n < 0 then r := 0;
  Result := r;
end;

function Comb(n, k: Integer): Int64;
var i: Integer; r: Int64;
begin
  { Multiplicative form, dividing as it goes: the partial product r*(n-k+i) is
    always divisible by i, so this stays exact and overflows far later than
    n!/(k!(n-k)!) computed literally would. }
  if (k < 0) or (n < 0) or (k > n) then begin Result := 0; Exit; end;
  if k > n - k then k := n - k;
  r := 1;
  for i := 1 to k do
  begin
    r := r * (n - k + i);
    r := r div i;
  end;
  Result := r;
end;

function Power(base, exponent: Double): Double;
{ base^exponent over the double-double kernel, with IEEE's pow() edge cases.

  It used to be `Exp(exponent * Ln(base))` in plain doubles, which rounds three
  times (Ln, the product, Exp) — Power(3, 7) came out one ulp above 2187 where
  libm gives it EXACTLY, and 2^0.5 and 1.5^2.5 were a ulp off too. Carrying
  y*log(x) as a dd fixes all three: the product keeps its low bits instead of
  losing them before the exponential.

  The old version also answered 0.0 for every base <= 0, which is wrong for the
  cases IEEE defines: (-2)^3 is -8, 0^0 is 1, and a negative base with a
  non-integer exponent is a domain error (NaN), not zero. }
var
  ax, ay, r: Double;
  w, p: TDd;
  k: Integer;
  yint, yodd, neg: Boolean;
begin
  if exponent = 0.0 then begin Result := 1.0; Exit; end;     { incl. NaN base }
  if base = 1.0 then begin Result := 1.0; Exit; end;         { incl. NaN exponent }
  if (base <> base) or (exponent <> exponent) then
  begin Result := base + exponent; Exit; end;                { NaN }
  ay := Abs(exponent);
  { integer exponent? anything >= 2^53 is necessarily an even integer }
  yint := (ay >= 9007199254740992.0) or (DdRint(exponent) = exponent);
  yodd := yint and (ay < 9007199254740992.0) and (FMod(exponent, 2.0) <> 0.0);
  if base = 0.0 then
  begin
    if exponent < 0.0 then
    begin
      if yodd then Result := 1.0 / base else Result := 1.0 / (base * base);
      Exit;
    end;
    if yodd then Result := base else Result := 0.0;          { keeps -0 for odd y }
    Exit;
  end;
  if ay > 1.7976931348623157e308 then                        { |y| = Inf }
  begin
    if base = -1.0 then begin Result := 1.0; Exit; end;
    ax := Abs(base);
    if ax < 1.0 then
    begin
      if exponent > 0.0 then Result := 0.0 else Result := ay;
    end
    else
    begin
      if exponent > 0.0 then Result := ay else Result := 0.0;
    end;
    Exit;
  end;
  if Abs(base) > 1.7976931348623157e308 then                 { |x| = Inf }
  begin
    if base > 0.0 then
    begin
      if exponent > 0.0 then Result := base else Result := 0.0;
      Exit;
    end;
    if exponent > 0.0 then
    begin
      if yodd then Result := base else Result := -base;
      Exit;
    end;
    if yodd then Result := DdBits($8000000000000000) else Result := 0.0;
    Exit;
  end;
  neg := False;
  ax := base;
  if base < 0.0 then
  begin
    if not yint then
    begin
      { negative base to a non-integer power: domain error }
      Result := (base - base) / (base - base);
      Exit;
    end;
    neg := yodd;
    ax := -base;
  end;
  w := DdLogD(ax);
  p := Dd2Prod(w.Hi, exponent);
  p.Lo := p.Lo + w.Lo * exponent;
  w := DdFast2Sum(p.Hi, p.Lo);
  if w.Hi > 710.0 then
  begin
    r := DdLdexp(1.0, 1024) * 2.0;
    if neg then Result := -r else Result := r;
    Exit;
  end;
  if w.Hi < -746.0 then
  begin
    r := DdBits(1) * 0.5;
    if neg then Result := -r else Result := r;
    Exit;
  end;
  r := DdScale(DdExpCore(w, k), k);
  if neg then Result := -r else Result := r;
end;

function IntPower(base: Double; n: Integer): Double;
{ square-and-multiply; negative n -> reciprocal. Accumulate in a local. }
var res, b: Double; e: Integer;
begin
  res := 1.0;
  b := base;
  e := n;
  if e < 0 then e := -e;
  while e > 0 do
  begin
    if (e and 1) = 1 then res := res * b;
    b := b * b;
    e := e div 2;
  end;
  if n < 0 then res := 1.0 / res;
  Result := res;
end;

{ ---- out-of-range float -> int: SATURATE, do not raise ----

  A double that no integer can hold used to reach the hardware conversion and
  come back as the x86 "integer indefinite" value, INT64_MIN. `Floor64(1e30)`
  was -9223372036854775808 and `Floor(1e30)` was **0**, because narrowing
  INT64_MIN to Integer keeps its low 32 bits, which are zero. 0 is the
  dangerous one: an out-of-range MAGNITUDE became the SMALLEST possible answer,
  so a guard like `if Floor(x) > limit` passed.

  FPC raises EInvalidOp here. We deliberately do not
  ([[decide-may-uses-math-cost-the-heap-and-exception-runtime]], user
  2026-08-14: *"We do it our way unless strict-fpc is set."*) — raising means
  `uses sysutils` in this unit, which is the only way to reach `Exception` at
  all, and that measured at roughly DOUBLE the code and QUADRUPLE the bss for
  any program that says `uses math`:

    bare 52 KB code / 9.5 KB bss · +math 123/9.5 · +math,sysutils 251/42.7

  On an ESP32 that is decisive, and FPC's raising is a software policy anyway —
  it UNMASKS the FP exceptions that x86, ARM, RISC-V and Xtensa all leave
  masked. pxx follows IEEE masked semantics by design (`1/0` is `Inf` here and
  a runtime error in FPC), so making Floor alone raise would be an island in our
  own behaviour. The raise belongs behind an opt-in flag, filed separately.

  Saturation is to the RETURN TYPE, which is why Floor tests before delegating
  rather than narrowing Floor64's saturated result: `Integer(High(Int64))` is
  -1, a nonsense answer, where `High(Integer)` is the useful one.

  WHAT IS NOT SATURATED, and this is the subtle half: only the INT64 conversion
  is policed. `Floor(3e9)` converts to Int64 perfectly well and then wraps on
  the narrowing to Integer — measured, FPC returns -1294967296 there and does
  NOT raise, and this unit's own header already documents that "the Integer
  forms overflow past 2^31 exactly as FPC's do". So 3e9 keeps wrapping and only
  1e30 saturates. Guarding the Integer range instead would have looked more
  correct and diverged from FPC on a case FPC defines.

  NaN takes the NEGATIVE sentinel rather than a third answer: it has no
  magnitude, so no bound is right, and Low() is both what the x86 conversion
  already delivered for it and out-of-band enough not to read as data. It is a
  judgement call, not a measurement — the decision covers magnitudes only. }
const
  { 2^63 exactly. A double cannot represent High(Int64), so the boundary test
    is "magnitude >= 2^63" — that value IS representable and is the true edge.
    -2^63 itself converts fine, hence >= on one side and < on the other.

    NaN needs no separate test in this form: it compares false against both
    bounds, so the `and` is false and the `not` fires. That is why the guard is
    a NEGATED IN-RANGE test rather than an out-of-range test — the latter
    silently lets NaN through. }
  TWO_POW_63 = 9223372036854775808.0;

{ Cold paths: reached only for a magnitude past Int64/Integer or a NaN, so the
  branch here costs nothing on the ordinary path. `x > 0.0` is false for NaN,
  which is how NaN lands on Low() without a test of its own. }
function SaturateInt64(x: Double): Int64;
begin
  if x > 0.0 then Result := High(Int64) else Result := Low(Int64);
end;

function SaturateInteger(x: Double): Integer;
begin
  if x > 0.0 then Result := High(Integer) else Result := Low(Integer);
end;

function Floor64(x: Double): Int64;
var t: Double;
begin
  if not ((x >= -TWO_POW_63) and (x < TWO_POW_63)) then
  begin
    Result := SaturateInt64(x);
    Exit;
  end;
  t := Int(x);
  if (x < 0.0) and (t <> x) then t := t - 1.0;
  Result := Trunc(t);
end;

function Ceil64(x: Double): Int64;
var t: Double;
begin
  if not ((x >= -TWO_POW_63) and (x < TWO_POW_63)) then
  begin
    Result := SaturateInt64(x);
    Exit;
  end;
  t := Int(x);
  if (x > 0.0) and (t <> x) then t := t + 1.0;
  Result := Trunc(t);
end;

function Floor(x: Double): Integer;
begin
  { tested here too, and deliberately: the saturation target is the RETURN
    type, so this cannot just narrow Floor64's answer. In range, the second
    test inside Floor64 is a predicted-taken branch. }
  if not ((x >= -TWO_POW_63) and (x < TWO_POW_63)) then
    Result := SaturateInteger(x)
  else
    Result := Integer(Floor64(x));
end;

function Ceil(x: Double): Integer;
begin
  if not ((x >= -TWO_POW_63) and (x < TWO_POW_63)) then
    Result := SaturateInteger(x)
  else
    Result := Integer(Ceil64(x));
end;

function FMod(x, y: Double): Double;
{ truncated remainder: x - trunc(x/y)*y, sign of x }
begin
  if y = 0.0 then begin Result := 0.0; Exit; end;
  Result := x - Int(x / y) * y;
end;

function Sign(x: Double): Integer;
begin
  if x > 0.0 then Result := 1
  else if x < 0.0 then Result := -1
  else Result := 0;
end;

function Min(a, b: Double): Double;
begin
  if a < b then Result := a else Result := b;
end;

function Max(a, b: Double): Double;
begin
  if a > b then Result := a else Result := b;
end;

function DegToRad(d: Double): Double;
begin
  Result := d * 3.14159265358979323846 / 180.0;
end;

function RadToDeg(r: Double): Double;
begin
  Result := r * 180.0 / 3.14159265358979323846;
end;

{ ================= Single overloads ================= }

function Abs(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Abs(d);
end;

function Sqrt(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Sqrt(d);
end;

function Exp(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Exp(d);
end;

function Ln(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Ln(d);
end;

function Sin(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Sin(d);
end;

function Cos(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Cos(d);
end;

function Tan(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Tan(d);
end;

function ArcSin(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := ArcSin(d);
end;

function ArcCos(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := ArcCos(d);
end;

function ArcTan(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := ArcTan(d);
end;

function Sinh(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Sinh(d);
end;

function Cosh(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Cosh(d);
end;

function Tanh(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Tanh(d);
end;

function Log10(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Log10(d);
end;

function Log2(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Log2(d);
end;

function Hypot(x, y: Single): Single;
var dx, dy: Double;
begin
  dx := x;
  dy := y;
  Result := Hypot(dx, dy);
end;

function Power(base, exponent: Single): Single;
var b, e: Double;
begin
  b := base;
  e := exponent;
  Result := Power(b, e);
end;

function Floor(x: Single): Integer;
var d: Double;
begin
  d := x;
  Result := Floor(d);
end;

function Ceil(x: Single): Integer;
var d: Double;
begin
  d := x;
  Result := Ceil(d);
end;

{ ================= Integer helpers ================= }

function Abs(x: Integer): Integer;
begin
  if x < 0 then Result := -x else Result := x;
end;

function Abs(x: Int64): Int64;
begin
  if x < 0 then Result := -x else Result := x;
end;

function Min(a, b: Integer): Integer;
begin
  if a < b then Result := a else Result := b;
end;

function Max(a, b: Integer): Integer;
begin
  if a > b then Result := a else Result := b;
end;

function Power(base, exponent: Integer): Integer;
var i, res: Integer;
begin
  res := 1;
  for i := 1 to exponent do
    res := res * base;
  Result := res;
end;

function Gcd(a, b: Integer): Integer;
var temp, x, y: Integer;
begin
  x := a;
  y := b;
  while y <> 0 do
  begin
    temp := y;
    y := x mod y;
    x := temp;
  end;
  Result := x;
end;

function Lcm(a, b: Integer): Integer;
begin
  if (a = 0) or (b = 0) then Result := 0
  else Result := (a * b) div Gcd(a, b);
end;

end.
