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
{ The PORTABLE square root — Newton plus an exact-residual correction plus a
  neighbour decision. On x86-64 `Sqrt` is one `sqrtsd` instruction instead
  (IEEE requires that to be correctly rounded, and it is ~2x faster than the
  software path this file used to run there), so this name exists to keep the
  portable path COMPILED and CALLABLE on the machine the gate runs on: without
  it, the code every other target executes would only ever be exercised by the
  cross sweep. lib_math_correctly_rounded asserts the two agree. }
function SqrtSoft(x: Double): Double;
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

{ ---- float-exception mask (FPC's Math-unit surface) ----

  x86-64 ONLY, and deliberately ABSENT rather than stubbed elsewhere: the
  __pxxGetFPUMask/__pxxSetFPUMask intrinsics are a compile-time Error on every
  other target (i386 not ported; aarch64/arm32/riscv32 have no architecturally
  guaranteed trap enable). A stub answering "everything is masked" would be a
  lie a caller cannot detect, so a non-x86-64 build fails to compile the CALL,
  which is the same refusal the compiler makes.

  pxx's default is quiet IEEE — every exception masked, so nothing traps
  (user decision, 2026-07-02). This API lets a program OPT IN; it does not
  unmask anything at startup, and FPC's default differs (FPC leaves invalid /
  zero-divide / overflow UNmasked so they surface as Pascal exceptions). Do not
  "fix" that difference here.

  SetExceptionMask returns the PREVIOUS mask — measured against FPC 3.2.2, and
  the opposite of what the ticket predicted, so save-and-restore reads:

      old := SetExceptionMask(GetExceptionMask - [exZeroDivide]);
      ...
      SetExceptionMask(old);

  A SIGFPE handler must NOT re-mask and return: sigreturn restores the FP state
  from the ucontext and the instruction traps again forever. Recover through
  __pxxSigPCPtr, or halt.
  ([[feature-b-fpc-exception-mask-api-in-math]]) }
{$ifdef CPUX86_64}
type
  { the six in x87/MXCSR mask-bit order, which is also FPC's declaration order
    and the order the intrinsics' 6-bit integer uses — one encoding, not three }
  TFPUException = (exInvalidOp, exDenormalized, exZeroDivide,
                   exOverflow, exUnderflow, exPrecision);
  TFPUExceptionMask = set of TFPUException;

function GetExceptionMask: TFPUExceptionMask;
function SetExceptionMask(const m: TFPUExceptionMask): TFPUExceptionMask;
{$endif}

implementation

{$ifdef CPUX86_64}
{ set <-> the intrinsics' 6-bit integer, 1 = masked. Nothing else lives here:
  the compiler already chose this encoding so the wrapper is a conversion. }
function MaskToBits(const m: TFPUExceptionMask): Integer;
var e: TFPUException;
begin
  Result := 0;
  for e := Low(TFPUException) to High(TFPUException) do
    if e in m then Result := Result or (1 shl Ord(e));
end;

function BitsToMask(bits: Integer): TFPUExceptionMask;
var e: TFPUException;
begin
  Result := [];
  for e := Low(TFPUException) to High(TFPUException) do
    if (bits and (1 shl Ord(e))) <> 0 then Result := Result + [e];
end;

function GetExceptionMask: TFPUExceptionMask;
begin
  Result := BitsToMask(__pxxGetFPUMask);
end;

function SetExceptionMask(const m: TFPUExceptionMask): TFPUExceptionMask;
begin
  { __pxxSetFPUMask is an EXPRESSION that hands back the previous mask, so the
    swap is one call and cannot race with itself — no read-then-write pair. }
  Result := BitsToMask(__pxxSetFPUMask(MaskToBits(m)));
end;
{$endif}

type
  PSqrtInt64  = ^Int64;    { double<->bits reinterpret for the Sqrt seed }
  PSqrtDouble = ^Double;
  PDdRawI64 = ^Int64;

{ ================= Double core ================= }

function Pi: Double;
begin
  Result := 3.14159265358979323846;
end;

function Abs(x: Double): Double;
begin
  if x < 0.0 then Result := -x else Result := x;
end;

{ The EXACT residual x - g*g, by a Dekker split of g into gh+gl (hi 26 bits +
  lo) so that gh*gh, gh*gl and gl*gl are each exact; then g*g is p (rounded)
  plus e (its exact error), and the residual is (x - p) - e. 134217729 = 2^27+1.
  Caller must ensure g*g does not overflow. }
function SqrtResid(x, g: Double): Double;
var c, gh, gl, p, e: Double;
begin
  p  := g * g;
  c  := g * 134217729.0;
  gh := c - (c - g);
  gl := g - gh;
  e  := ((gh * gh - p) + 2.0 * gh * gl) + gl * gl;
  Result := (x - p) - e;
end;

function SqrtSoft(x: Double): Double;
{ Newton-Raphson to ~1 ULP, then ONE correctly-rounded correction step using an
  exact residual. Plain Newton has an FP fixed point that can sit 1 ULP below the
  correctly-rounded root (sqrt(2) landed at ...bcc vs the IEEE ...bcd), and every
  RTL routine built on Sqrt inherited that error. The correction computes the
  exact residual r = x - g*g with a Dekker two-product (no FMA needed), then
  applies r/(2g): sqrt(x) = g*sqrt(1+r/g^2) ~= g + r/(2g) to well past double
  precision, so rounding g + r/(2g) yields the correctly-rounded result. }
const
  { the smallest NORMAL double, and an exact power-of-two pair for rescaling a
    denormal into the normal range: 2^106 up, 2^53 down (106 is even, so the
    square root halves it to 53 exactly). }
  MIN_NORMAL = 2.2250738585072014e-308;
  TWO_POW_106 = 81129638414606681695789005144064.0;
  TWO_POW_53  = 9007199254740992.0;
  { exact decimal expansions of 2^-32 and 2^-64, so the value does not depend on
    how the literal parser rounds }
  TWO_POW_M32 = 2.3283064365386962890625e-10;
  TWO_POW_M64 = 5.42101086242752217003726400434970855712890625e-20;
  TWO_POW_32  = 4294967296.0;
  TWO_POW_64  = 18446744073709551616.0;
var g, ng, z, r, res, nb, r2, r3, sx, sc, gs: Double; i: Integer; bits: Int64;
begin
  { FPC-faithful IEEE: Sqrt of a negative is NaN (C sqrt() binds here and expects
    NaN too). z/z with z=0 yields a NaN without a NaN literal.

    The special values are checked BEFORE the bit-hack seed, because the seed
    assumes a normalised double and every one of these breaks that assumption.
    Ln next door already had the full set; Sqrt had only the first two, which is
    the sibling-case smell.
    ([[bug-b-sqrt-of-infinity-answers-nan]]) }
  if x <> x then begin Result := x; Exit; end;              { NaN in, NaN out }
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;   { incl. -Inf }
  { Sqrt(0) is 0 WITH THE ARGUMENT'S SIGN: IEEE 754 says sqrt(-0) is -0, and
    `x = 0.0` is true for both zeros, so returning x rather than 0.0 carries the
    sign. Returning the literal gave +0 for -0. }
  if x = 0.0 then begin Result := x; Exit; end;
  { +Inf: sqrt(+Inf) is +Inf. It passed both guards above and reached the seed,
    where Newton cannot converge on an infinite residual and landed on NaN —
    which Hypot, vector lengths and the statistics routines then inherited.
    (x - x) is NaN for an infinity and 0 for anything finite. }
  if (x - x) <> 0.0 then begin Result := x; Exit; end;
  { DENORMALS: the seed halves the raw exponent FIELD, which is 0 for a
    subnormal and carries no implicit leading 1, so the seed is meaningless and
    eight Newton steps cannot recover. Measured before this guard:
    Sqrt(5e-324) answered 2.185e-157 where libm says 2.223e-162 — five orders of
    magnitude out, and silently. Scaling by an exact power of two costs nothing
    and is exact in both directions: verified against libm on 20,006 denormals,
    zero mismatches. }
  if x < MIN_NORMAL then
  begin
    Result := Sqrt(x * TWO_POW_106) / TWO_POW_53;
    Exit;
  end;
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
  { ONE exact power-of-two scaling covers the whole correction. It is needed
    lower than it looks: the guard here used to be "g*g overflowed, skip the
    correction", but the Dekker split squares gh, which is g rounded UP to 26
    bits, so gh*gh reaches +Inf while g*g is still finite. The residual then
    came back -Inf and Sqrt answered -Inf for the doubles just below DBL_MAX.
    Scaling x by 2^-64 and the root by 2^-32 is exact — both are powers of two
    and x is enormous on this path, so nothing rounds and nothing underflows —
    and it removes the special case instead of adding a second one. }
  if g > 1.0e150 then
  begin
    sx := x * TWO_POW_M64;
    sc := TWO_POW_M32;
  end
  else if g < 1.0e-150 then
  begin
    { and UP at the other end, for the mirror-image reason: there the split's
      SMALLEST term, gl*gl, falls below the subnormal threshold and flushes to
      zero, so the residual is no longer exact and the neighbour decision is
      made on a wrong number. Four values in a 65,000-value sweep, all with
      x ~ 1e-307 — the same defect at the opposite end of the range. }
    sx := x * TWO_POW_64;
    sc := TWO_POW_32;
  end
  else
  begin
    sx := x;
    sc := 1.0;
  end;
  gs := g * sc;
  { residual and correction in the scaled domain: with r = xs - gs^2 = sc^2*(x -
    g^2), the true r/(2g) is r/(2*gs*sc). }
  r := SqrtResid(sx, gs);
  res := g + r / (2.0 * gs * sc);

  { The correction alone is NOT always correctly rounded — it was 1 ulp low on
    ordinary normals such as 2.215827865120445e276 and on DBL_MAX itself, with
    no special value or overflow edge involved
    ([[bug-b-sqrt-is-1-ulp-low-on-some-normal-inputs]]). `r/(2g)` is a rounded
    quotient added to a rounded g, so the sum can land on the wrong side of the
    halfway point.

    So DECIDE it instead of trusting it: take the residual of the answer, and
    if it is not zero compare it against the residual of the NEIGHBOURING
    double in the direction the residual points. Whichever root has the smaller
    |x - root^2| is the nearer one, and that IS the correctly-rounded result —
    a measurement rather than an estimate. res > 0 here, so the bit pattern is
    monotone in the value and +-1 on the bits is exactly the neighbour. The
    same scaling carries through: it multiplies both residuals by 2^-64, which
    cannot change which magnitude is smaller. }
  r2 := SqrtResid(sx, res * sc);
  if r2 = 0.0 then begin Result := res; Exit; end;         { x is a perfect square }
  bits := PSqrtInt64(@res)^;
  if r2 > 0.0 then bits := bits + 1 else bits := bits - 1;
  nb := PSqrtDouble(@bits)^;
  r3 := SqrtResid(sx, nb * sc);
  if Abs(r3) < Abs(r2) then Result := nb else Result := res;
end;

{ x86-64: `sqrtsd` IS the correctly-rounded square root — IEEE 754 requires
  sqrt to be exact, and unlike the transcendentals the hardware really does
  deliver it, including for subnormals, +-0, +Inf and the NaN for a negative.
  So the whole of SqrtSoft above collapses to one instruction here, and it
  measured 2x faster than the software path on a 3M-call loop (269 ms -> 575 ms
  was the cost of making the software path correctly rounded; this takes it
  back and then some).

  Every other target keeps SqrtSoft, which is why that function stays exported
  and tested rather than becoming dead code on the machine we gate on. }
{$ifdef CPUX86_64}
function Sqrt(x: Double): Double;
var r: Double;
begin
  asm
    movsd  xmm0, x
    sqrtsd xmm0, xmm0
    movsd  r, xmm0
  end;
  Result := r;
end;
{$else}
function Sqrt(x: Double): Double;
begin
  Result := SqrtSoft(x);
end;
{$endif}

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

  { sin and cos of one argument, computed together — the reduction and the
    quadrant fold are shared, so returning both costs almost nothing over one.

    A RECORD rather than two `var sn, cs: Double` out-parameters, and that is
    load-bearing on i386: any access through a by-reference FLOAT parameter
    faults there
    ([[bug-a-i386-var-float-parameter-faults-on-first-access]]), while a record
    by reference is fine. It also matches SinCosDd, which pairs its two TDds
    the same way. Revert to plain out-parameters only if that bug is fixed AND
    the pair reads better, which it does not. }
  TSinCos = record
    Sn: Double;
    Cs: Double;
  end;

function DdBits(b: Int64): Double;
begin
  Result := PSqrtDouble(@b)^;
end;

{ the other direction — a double's bit pattern, for the exponent extraction the
  fast log/exp reductions do }
function DdRawBits(x: Double): Int64;
begin
  Result := PDdRawI64(@x)^;
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

{ Square root of a dd: one Newton correction on top of the double sqrt, which
  is enough because the residual a - y0^2 is computed exactly. }
function DdSqrt(a: TDd): TDd;
var y0: Double; y, e: TDd;
begin
  if a.Hi = 0.0 then begin Result := a; Exit; end;
  y0 := Sqrt(a.Hi);
  y.Hi := y0; y.Lo := 0.0;
  e := DdAdd(a, DdMulD(DdMul(y, y), -1.0));      { a - y0^2 }
  y.Lo := e.Hi / (2.0 * y0);
  Result := DdFast2Sum(y.Hi, y.Lo);
end;

{ pi and pi/2 as dds, from bits (see the kernel header on why not decimals). }
function DdPio2: TDd;
begin
  Result.Hi := DdBits($3FF921FB54442D18);
  Result.Lo := DdBits($3C91A62633145C07);
end;

function DdPi: TDd;
begin
  Result.Hi := DdBits($400921FB54442D18);
  Result.Lo := DdBits($3CA1A62633145C07);
end;

{ atan of a NON-NEGATIVE dd. t > 1 inverts around pi/2; then the half-angle
  t := t/(1+sqrt(1+t^2)) until t < 2^-4 (h doublings to undo), then a 13-term
  alternating odd series, then the doublings back — which are exact, being
  multiplications by 2.

  This replaces the plain-double reduce-and-Taylor ArcTan that used to live
  here. Measured before the port: 2065 of 3005 random arguments disagreed with
  libm, up to 4 ulp — so the claim in
  [[bug-b-arcsin-arccos-lose-2-ulps-vs-libm]] that "ArcTan agrees exactly" was
  a sample of one (atan(2.0), which happens to be right). }
function DdAtan(t: TDd): TDd;
var u, s, one: TDd; h, k: Integer; invert: Boolean;
begin
  one.Hi := 1.0; one.Lo := 0.0;
  h := 0; invert := False;
  if t.Hi > 1.0 then
  begin
    invert := True;
    t := DdDiv(one, t);
  end;
  while (t.Hi >= 0.0625) and (h < 6) do
  begin
    u := DdSqrt(DdAddD(DdMul(t, t), 1.0));
    t := DdDiv(t, DdAddD(u, 1.0));
    h := h + 1;
  end;
  u := DdMul(t, t);                      { <= 2^-8 }
  s := DdDivD(one, 27.0);
  for k := 12 downto 0 do
  begin
    s := DdMul(u, s);
    s := DdAdd(DdDivD(one, Double(2 * k + 1)), DdMulD(s, -1.0));
  end;
  s := DdMul(t, s);
  while h > 0 do begin s := DdMulD(s, 2.0); h := h - 1; end;
  if invert then s := DdAdd(DdPio2, DdMulD(s, -1.0));
  Result := s;
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
  { Trunc(), not Int() and not Floor(). Floor returns a 32-bit Integer which
    would SILENTLY OVERFLOW for a between 2^31 and 2^52 — a range this function
    is explicitly still handling. Int() reads better and is what this used to
    say, but it saturates to 32 bits on i386 and arm32
    ([[bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32]]),
    which is the same trap one level down. Today's callers all stay under 2^31
    so nothing was observably wrong here — this is closing the latent half.
    Trunc is 64-bit and right on every target; a is non-negative, so truncation
    and floor agree. }
  t := Double(Trunc(a));
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

{ ================= the FAST log / exp family =================

  Same split as the trig above, and the same reason: the double-double Ln/Exp
  are correctly rounded and 1270x slower than glibc — the worst ratio in the
  RTL, and it sits under Log10, Log2, LogN, Power and every `x ** y` in NilPy.
  devdocs/dev/float-policy.md is the policy; these are the default path and the
  dd ones stay behind -dPXX_FLOAT_EXACT.

  Both are the fdlibm minimax kernels (Sun Microsystems, freely distributable),
  the same source as the sin/cos ones. Accuracy is < 1 ulp; the structure is
  what buys it, not the polynomial degree:

  - Ln reduces x = 2^k * m with m in [sqrt(2)/2, sqrt(2)) by EXPONENT
    EXTRACTION, which is exact, and then evaluates log(m) through
    s = f/(2+f) — an odd series in s converges far faster than one in f and,
    more importantly, s is small so the polynomial never has to fight
    cancellation.
  - Exp reduces x = k*ln2 + r with ln2 carried as a hi/lo PAIR, so the
    reduction keeps ~106 bits even though the kernel is plain double. That is
    the same "reduction stays exact in both modes" rule the trig path follows.

  The k*ln2 hi/lo split is why LN2HI has its low 32 bits zero: k*LN2HI is then
  an EXACT product for every k in range, and the whole reduction error lives in
  the k*LN2LO term. }
const
  { log(1+f) minimax coefficients over s = f/(2+f) }
  LG1 = 6.666666666666735130e-01;   LG2 = 3.999999999940941908e-01;
  LG3 = 2.857142874366239149e-01;   LG4 = 2.222219843214978396e-01;
  LG5 = 1.818357216161805012e-01;   LG6 = 1.531383769920937332e-01;
  LG7 = 1.479819860511658591e-01;
  { exp(r) minimax coefficients, |r| <= 0.5*ln2 }
  EP1 =  1.66666666666666019037e-01;  EP2 = -2.77777777770155933842e-03;
  EP3 =  6.61375632143793436117e-05;  EP4 = -1.65339022054652515390e-06;
  EP5 =  4.13813679705723846039e-08;

function FastLnBits(x: Double): Double;
{ x MUST be finite and > 0 — every caller guards NaN/0/negative/Inf first. }
var
  b, lowHalf: Int64;
  hx, ii, jj, k: Integer;
  f, sred, z, rpoly, w, t1, t2, dk, hfsq, ln2hi, ln2lo, xx: Double;
begin
  ln2hi := DdBits($3FE62E42FEE00000);      { ln2, high 32 bits of mantissa }
  ln2lo := DdBits($3DEA39EF35793C76);      { ...and the rest }
  xx := x;
  b := DdRawBits(xx);
  hx := Integer(b shr 32);
  k := 0;
  if hx < $00100000 then                   { subnormal: scale up by 2^54 first }
  begin
    k := -54;
    xx := xx * DdBits($4350000000000000);
    b := DdRawBits(xx);
    hx := Integer(b shr 32);
  end;
  k := k + ((hx shr 20) - 1023);
  hx := hx and $000FFFFF;
  { pick the binade so m lands in [sqrt(2)/2, sqrt(2)) — the magic constant is
    the mantissa of sqrt(2) rounded, and the `and $100000` asks which side of
    it hx falls on }
  ii := (hx + $95F64) and $100000;
  lowHalf := b and $00000000FFFFFFFF;
  b := (Int64(hx or (ii xor $3FF00000)) shl 32) or lowHalf;
  xx := DdBits(b);
  k := k + (ii shr 20);
  f := xx - 1.0;
  dk := Double(k);
  if ((hx + 2) and $000FFFFF) < 3 then     { |f| < 2^-20: the series is overkill }
  begin
    if f = 0.0 then
    begin
      if k = 0 then begin Result := 0.0; Exit; end;
      Result := dk * ln2hi + dk * ln2lo;
      Exit;
    end;
    rpoly := f * f * (0.5 - 0.33333333333333333 * f);
    if k = 0 then Result := f - rpoly
    else Result := dk * ln2hi - ((rpoly - dk * ln2lo) - f);
    Exit;
  end;
  sred := f / (2.0 + f);
  z := sred * sred;
  w := z * z;
  t1 := w * (LG2 + w * (LG4 + w * LG6));
  t2 := z * (LG1 + w * (LG3 + w * (LG5 + w * LG7)));
  rpoly := t2 + t1;
  ii := hx - $6147A;
  jj := $6B851 - hx;
  { the two forms differ only in whether 0.5*f*f is split out; the second is
    for f near the middle of the range, where f - s*(f-R) would cancel }
  if (ii or jj) > 0 then
  begin
    hfsq := 0.5 * f * f;
    if k = 0 then Result := f - (hfsq - sred * (hfsq + rpoly))
    else Result := dk * ln2hi - ((hfsq - (sred * (hfsq + rpoly) + dk * ln2lo)) - f);
  end
  else
  begin
    if k = 0 then Result := f - sred * (f - rpoly)
    else Result := dk * ln2hi - ((sred * (f - rpoly) - dk * ln2lo) - f);
  end;
end;

function FastExpD(x: Double): Double;
{ x MUST be finite and inside (-746, 710) — the caller handles the edges. }
var
  hi, lo, t, c, y, xx, ax, ln2hi, ln2lo: Double;
  k: Integer;
begin
  ln2hi := DdBits($3FE62E42FEE00000);
  ln2lo := DdBits($3DEA39EF35793C76);
  xx := x;
  ax := Abs(xx);
  hi := 0.0; lo := 0.0; k := 0;
  if ax > 0.34657359027997264 then                 { > 0.5*ln2: reduce }
  begin
    if ax < 1.0397207708399179 then                { < 1.5*ln2: k is +-1 }
    begin
      if xx > 0.0 then begin hi := xx - ln2hi; lo := ln2lo; k := 1; end
      else begin hi := xx + ln2hi; lo := -ln2lo; k := -1; end;
    end
    else
    begin
      if xx > 0.0 then k := Trunc(DdBits($3FF71547652B82FE) * xx + 0.5)
      else k := Trunc(DdBits($3FF71547652B82FE) * xx - 0.5);
      t := Double(k);
      hi := xx - t * ln2hi;                        { exact: LN2HI's low bits are 0 }
      lo := t * ln2lo;
    end;
    xx := hi - lo;
  end
  else if ax < 3.725290298461914e-09 then          { |x| < 2^-28: 1+x IS the answer }
  begin
    Result := 1.0 + xx;
    Exit;
  end;
  t := xx * xx;
  c := xx - t * (EP1 + t * (EP2 + t * (EP3 + t * (EP4 + t * EP5))));
  if k = 0 then
  begin
    Result := 1.0 - ((xx * c) / (c - 2.0) - xx);
    Exit;
  end;
  y := 1.0 - ((lo - (xx * c) / (2.0 - c)) - hi);
  Result := DdLdexp(y, k);
end;

function FastLogSplit(x: Double; var k: Integer): Double;
{ x = 2^kk * m with m in [sqrt(2)/2, sqrt(2)). The exponent comes out by bit
  extraction, so it is EXACT — which is the whole point: a power of two returns
  m = 1.0 and the answer is the integer kk with nothing left to round. That is
  what keeps Log2(2^n) and Log10(10^n) clean, and it is why these do not simply
  scale FastLnBits by 1/ln2 (which would round twice, once in the log and once
  in the multiply).

  `var k: Integer` is safe on i386; a `var Double` would not be
  ([[bug-a-i386-var-float-parameter-faults-on-first-access]]), hence m coming
  back as the RESULT rather than a second out-parameter. }
var b, lowHalf: Int64; hx, ii, kk: Integer; xx: Double;
begin
  xx := x;
  b := DdRawBits(xx);
  hx := Integer(b shr 32);
  kk := 0;
  if hx < $00100000 then                     { subnormal: scale up by 2^54 }
  begin
    kk := -54;
    xx := xx * DdBits($4350000000000000);
    b := DdRawBits(xx);
    hx := Integer(b shr 32);
  end;
  kk := kk + ((hx shr 20) - 1023);
  hx := hx and $000FFFFF;
  ii := (hx + $95F64) and $100000;
  lowHalf := b and $00000000FFFFFFFF;
  { ii xor $3FF00000 is $3FF00000 (2^0) when ii = 0 and $3FE00000 (2^-1) when
    ii = $100000 — i.e. it picks the binade that lands m around 1 }
  b := (Int64(hx or (ii xor $3FF00000)) shl 32) or lowHalf;
  kk := kk + (ii shr 20);
  k := kk;
  Result := DdBits(b);
end;

function FastLog10D(x: Double): Double;
{ log10(x) = k*log10(2) + log10(m). log10(2) is carried as a hi/lo pair so the
  k term keeps its low bits — with k up to 1074 a single rounded log10(2) would
  cost several ulp at the top of the range. }
var k: Integer; m, y, z: Double;
begin
  m := FastLogSplit(x, k);
  y := Double(k);
  z := y * DdBits($3D59FEF311F12B36)                 { log10(2), low }
       + DdBits($3FDBCB7B1526E50E) * FastLnBits(m);  { (1/ln10) * ln m }
  Result := z + y * DdBits($3FD34413509F6000);       { log10(2), high }
end;

function FastLog2D(x: Double): Double;
var k: Integer; m: Double;
begin
  m := FastLogSplit(x, k);
  { k is exact and |log2(m)| <= 0.5, so the sum cannot cancel }
  Result := Double(k) + FastLnBits(m) * DdBits($3FF71547652B82FE);
end;

function Exp(x: Double): Double;
{ Correctly rounded, over the double-double kernel: reduce x = k*ln2 + r with
  ln2 carried to ~106 bits, Taylor e^r, then one rounding on the way out. The
  old plain-double version was ~1 ulp off (exp(1) came back as
  2.7182818284590446 against libm's 2.718281828459045). }
{$ifdef PXX_FLOAT_EXACT}
var a, sres: TDd; k: Integer;
{$endif}
begin
  if x <> x then begin Result := x; Exit; end;                { NaN }
  if x > 710.0 then begin Result := DdLdexp(1.0, 1024) * 2.0; Exit; end;   { +Inf }
  if x < -746.0 then begin Result := DdBits(1) * 0.5; Exit; end;           { +0 }
{$ifdef PXX_FLOAT_EXACT}
  a.Hi := x;
  a.Lo := 0.0;
  sres := DdExpCore(a, k);
  Result := DdScale(sres, k);
{$else}
  Result := FastExpD(x);
{$endif}
end;

function Ln(x: Double): Double;
{ Correctly rounded under -dPXX_FLOAT_EXACT; the fdlibm kernel by default. }
var z: Double;
{$ifdef PXX_FLOAT_EXACT}
    r: TDd;
{$endif}
begin
  { FPC-faithful IEEE: Ln(0) = -Inf, Ln(negative) = NaN (C log() binds here). }
  if x <> x then begin Result := x; Exit; end;
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
  if x = 0.0 then begin z := 0.0; Result := -1.0 / z; Exit; end;
  if x > 1.7976931348623157e308 then begin Result := x; Exit; end;   { +Inf }
{$ifdef PXX_FLOAT_EXACT}
  r := DdLogD(x);
  Result := r.Hi + r.Lo;
{$else}
  Result := FastLnBits(x);
{$endif}
end;

{ ================= trigonometry on the dd kernel =================

  What was here before was `r := x - Trunc(x/2pi) * 2pi` in plain double with a
  rounded 2pi, then a Taylor series. Measured against glibc, the error grew with
  the argument until nothing was left: 85 ulp at x=100, 1.2 MILLION at 1e6, and
  2.4 BILLION at 1e10, where the answer was uncorrelated with the true value.
  Two independent defects in that one line — the rounded 2pi (which is what
  argument reduction is a whole field about), and `Trunc(...)` into an INTEGER,
  which silently overflows past 2^31, i.e. beyond x ~ 1.3e10.

  This is the port of lib/crtl/src/math.c's reduction, which already got every
  one of those rows exactly right ([[bug-b-rtl-math-transcendentals-lose-argument-reduction]]).
  Third time this file has replaced a plain-double mechanism with the crtl dd
  one rather than patching it. }

{ floor as a Double. Three primitives were candidates and only one is correct
  here:
    - Floor() returns a 32-bit Integer, which the ~2^50 values the Payne-Hanek
      path feeds this would silently overflow;
    - Int() is the natural spelling — remove the fraction, stay in the float
      domain — but it SATURATES to 32 bits on i386 and arm32
      ([[bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32]]),
      which turned Sin(1e20) into NaN on exactly those two targets while
      x86-64, aarch64 and riscv32 were green;
    - Trunc() is 64-bit and correct on every target, so that is what this uses,
      with the sign correction Trunc does not do.
  Revert to Int() when that Track A bug lands (devdocs/dev/track-b-workarounds.md). }
function DdFloor(x: Double): Double;
var t: Double;
begin
  if Abs(x) >= 4503599627370496.0 then begin Result := x; Exit; end;  { >= 2^52 }
  t := Double(Trunc(x));
  if t > x then t := t - 1.0;
  Result := t;
end;

{ Cody-Waite reduction x = n*(pi/2) + r, |r| <= pi/4(1+eps), r as a dd.
  pi/2 is split into three 24-bit chunks — n*chunk is then EXACT for |n| < 2^28
  — plus a dd tail, so r carries about 2^-150 absolute error. That is enough for
  full relative accuracy even for the double closest to a multiple of pi/2
  (~2^-54 away). VALID FOR |x| < 1e8; past that the chunks no longer carry the
  bits the answer is made of, and the caller switches to Payne-Hanek.
  Returns the quadrant n mod 4. }
function TrigReduce(x: Double; var r: TDd): Integer;
var nd, s1, s2: Double; n: Int64; t, p: TDd;
begin
  nd := DdRint(x * DdBits($3FE45F306DC9C883));          { x * 2/pi }
  n := Trunc(nd);
  if n = 0 then
  begin
    r.Hi := x; r.Lo := 0.0;
    Result := 0;
    Exit;
  end;
  s1 := x  - nd * DdBits($3FF921FB60000000);            { pi/2 chunk A, exact }
  s2 := s1 - nd * DdBits($BE6777A5C0000000);            { chunk B, exact }
  t  := Dd2Sum(s2, -(nd * DdBits($BCDEE59DA0000000)));  { chunk C }
  p  := Dd2Prod(nd, DdBits($3B298A2E03707345));         { dd tail d1 }
  t  := DdAdd(t, DdMulD(p, -1.0));
  t.Lo := t.Lo - nd * DdBits($B7C6FDB1F7759834);        { d2 (tiny) }
  r := Dd2Sum(t.Hi, t.Lo);
  Result := Integer(n and 3);
end;

{ 2/pi as 24-bit chunks, 1440 bits — the table Payne-Hanek needs to reduce ANY
  double. 24 bits is not arbitrary: a 24x24-bit product is below 2^48 and so is
  EXACT in a double, which is what lets the convolution below run in plain
  double arithmetic with no int128 and no error terms. Copied from
  lib/crtl/src/math.c, where it was derived at 700 decimal digits and its
  leading entries checked against fdlibm's published ipio2. }
const
  IPIO2: array[0..59] of Double = (
    10680707.0,    7228996.0,    1387004.0,    2578385.0,
    16069853.0,   12639074.0,    9804092.0,    4427841.0,
    16666979.0,   11263675.0,   12935607.0,    2387514.0,
     4345298.0,   14681673.0,    3074569.0,   13734428.0,
    16653803.0,    1880361.0,   10960616.0,    8533493.0,
     3062596.0,    8710556.0,    7349940.0,    6258241.0,
     3772886.0,    3769171.0,    3798172.0,    8675211.0,
    12450088.0,    3874808.0,    9961438.0,     366607.0,
    15675153.0,    9132554.0,    7151469.0,    3571407.0,
     2607881.0,   12013382.0,    4155038.0,    6285869.0,
     7677882.0,   13102053.0,   15825725.0,     473591.0,
     9065106.0,   15363067.0,    6271263.0,    9264392.0,
     5636912.0,    4652155.0,    7056368.0,   13614112.0,
    10155062.0,    1944035.0,    9527646.0,   15080200.0,
     6658437.0,    6231200.0,    6832269.0,   16767104.0);

{ Payne-Hanek, for ax = |x| >= 1e8. Writing ax = X * 2^(e0-48) with X in three
  24-bit chunks and 2/pi as the chunk sum above, the product collects by
  k = i+j into terms C_k * 2^(e0-24(k+1)). Only the low two integer bits survive
  `mod 4`, so terms whose exponent is >= 2 contribute a multiple of 4 and are
  skipped outright — which is why the work is CONSTANT no matter how enormous x
  is. Returns the quadrant and sets r, |r| <= pi/4. }
function TrigReduceBig(ax: Double; var r: TDd): Integer;
var
  tx: array[0..2] of Double;
  z, ck, t, nd: Double;
  acc, fr: TDd;
  e0, k, kstart, i, j, ek, q: Integer;
begin
  e0 := 0;
  z := ax;
  while z >= 16777216.0 do begin z := z * 0.5; e0 := e0 + 1; end;
  while z < 8388608.0   do begin z := z * 2.0; e0 := e0 - 1; end;
  for i := 0 to 2 do
  begin
    tx[i] := Int(z);                     { z >= 0, so Int is the integral part }
    z := (z - tx[i]) * 16777216.0;
  end;

  kstart := 0;
  while (e0 - 24 * (kstart + 1)) > 1 do kstart := kstart + 1;

  acc.Hi := 0.0; acc.Lo := 0.0;
  for k := kstart to kstart + 7 do
  begin
    ek := e0 - 24 * (k + 1);
    ck := 0.0;
    for j := 0 to 2 do
    begin
      i := k - j;
      if (i >= 0) and (i < 60) then
        ck := ck + tx[j] * IPIO2[i];     { exact: each product < 2^48 }
    end;
    if ck <> 0.0 then
    begin
      t := DdLdexp(ck, ek);
      { Reduce mod 4 while t is still exactly representable. t carries 50
        significant bits; the residue needs at most 2 integer bits plus t's
        fractional bits, and whenever t >= 4 that total stays inside 53 — so
        this subtraction is EXACT, not merely close. }
      if (t >= 4.0) or (t <= -4.0) then t := t - 4.0 * DdFloor(t * 0.25);
      acc := DdAdd(acc, Dd2Sum(t, 0.0));
    end;
  end;

  { fold back into [0,4), then split into quadrant and a residue in [-1/2, 1/2]
    so that |r| <= pi/4 for the kernels }
  t := DdFloor((acc.Hi + acc.Lo) * 0.25);
  acc := DdAdd(acc, Dd2Sum(-4.0 * t, 0.0));
  nd := DdRint(acc.Hi + acc.Lo);
  fr := DdAdd(acc, Dd2Sum(-nd, 0.0));
  q := Integer(Trunc(nd) and 3);
  r := DdMul(fr, DdPio2);
  Result := q;
end;

{ ---- the FAST kernels (the DEFAULT) ----

  Minimax polynomials on the reduced argument, plain double, no divisions —
  fdlibm's __kernel_sin / __kernel_cos shape and coefficients (Sun
  Microsystems, freely distributable). About 1 ulp, which is libm's own
  accuracy class, at 0.029 us against the dd kernel's 7.96.

  `y` is the reduced argument's TAIL (r.Lo). Passing it in is what keeps this
  accurate near a multiple of pi/2, where r.Hi alone has lost most of its
  significant bits — the reduction stays exact in this mode, only the kernel
  is approximate. See devdocs/dev/float-policy.md. }
const
  KS1 = -1.66666666666666324348e-01;  KS2 =  8.33333333332248946124e-03;
  KS3 = -1.98412698298579493134e-04;  KS4 =  2.75573137070700676789e-06;
  KS5 = -2.50507602534068634195e-08;  KS6 =  1.58969099521155010221e-10;
  KC1 =  4.16666666666666019037e-02;  KC2 = -1.38888888888741095749e-03;
  KC3 =  2.48015872894767294178e-05;  KC4 = -2.75573143513906633035e-07;
  KC5 =  2.08757232129817482790e-09;  KC6 = -1.13596475577881948265e-11;

function FastSinK(x, y: Double): Double;
var z, v, r: Double;
begin
  z := x * x;
  v := z * x;
  r := KS2 + z * (KS3 + z * (KS4 + z * (KS5 + z * KS6)));
  { the tail enters as y - (z*(0.5*y - v*r) - v*KS1) rather than as a plain
    addition: sin(x+y) = sin x + y cos x to first order, and cos x is ~1 here }
  Result := x - ((z * (0.5 * y - v * r) - y) - v * KS1);
end;

function FastCosK(x, y: Double): Double;
var z, r, hz, a, qx, ax: Double;
begin
  z := x * x;
  r := z * (KC1 + z * (KC2 + z * (KC3 + z * (KC4 + z * (KC5 + z * KC6)))));
  ax := Abs(x);
  if ax < 0.3 then
  begin
    Result := 1.0 - (0.5 * z - (z * r - x * y));
    Exit;
  end;
  { fdlibm's split for the larger half of the range: subtracting a constant qx
    first keeps `1 - 0.5*z` from cancelling away the polynomial's contribution }
  if ax > 0.78125 then qx := 0.28125
  else qx := DdLdexp(ax, -2);
  hz := 0.5 * z - qx;
  a := 1.0 - qx;
  Result := a - (hz - (z * r - x * y));
end;

{ sin/cos of a reduced dd argument, |r| <= ~0.786, by a 13-term dd Taylor in
  Horner form. }
function SinKernel(r: TDd): TDd;
var r2, s: TDd; k: Integer;
begin
  r2 := DdMul(r, r);
  s.Hi := 1.0; s.Lo := 0.0;
  for k := 13 downto 1 do
  begin
    s := DdMul(DdDivD(r2, Double(2 * k * (2 * k + 1))), s);
    s := DdAdd(Dd2Sum(1.0, 0.0), DdMulD(s, -1.0));
  end;
  Result := DdMul(r, s);
end;

function CosKernel(r: TDd): TDd;
var r2, s: TDd; k: Integer;
begin
  r2 := DdMul(r, r);
  s.Hi := 1.0; s.Lo := 0.0;
  for k := 13 downto 1 do
  begin
    s := DdMul(DdDivD(r2, Double((2 * k - 1) * 2 * k)), s);
    s := DdAdd(Dd2Sum(1.0, 0.0), DdMulD(s, -1.0));
  end;
  Result := s;
end;

{ sin and cos together — they share the reduction and both kernels, and every
  caller here wants one or the other of the pair. q selects which.

  Used by the EXACT path only; the fast path is SinCosFast below, which shares
  the same reduction. }
procedure SinCosDd(x: Double; var sn, cs: TDd);
var r, a, b: TDd; q: Integer;
begin
  if Abs(x) >= 1.0e8 then q := TrigReduceBig(Abs(x), r)
  else q := TrigReduce(x, r);
  a := SinKernel(r);
  b := CosKernel(r);
  case q of
    0: begin sn := a; cs := b; end;
    1: begin sn := b; cs := DdMulD(a, -1.0); end;
    2: begin sn := DdMulD(a, -1.0); cs := DdMulD(b, -1.0); end;
  else begin sn := DdMulD(b, -1.0); cs := a; end;
  end;
end;

{ Plain-double Cody-Waite, for the fast path and moderate |x| (n fits 28 bits,
  i.e. |x| < ~4e8). Same three pi/2 chunks as TrigReduce — nd*chunk is exact for
  |n| < 2^28 — but the bookkeeping is four flops instead of ten dd CALLS, which
  is where the time actually went: with the dd reduction the fast kernels cost
  238 ms per 1M sin+cos pairs and the reduction cost another 770.

  The result is a head plus a tail, exactly what the kernels want. Above the
  chunk range this is not used and TrigReduce/TrigReduceBig take over, so the
  huge-argument accuracy is untouched. }
function FastTrigReduce(x: Double; var r: TDd): Integer;
var nd, s1, s2, t, lo: Double; n: Int64;
begin
  nd := DdRint(x * DdBits($3FE45F306DC9C883));          { x * 2/pi }
  n := Trunc(nd);
  if n = 0 then
  begin
    r.Hi := x; r.Lo := 0.0;
    Result := 0;
    Exit;
  end;
  s1 := x  - nd * DdBits($3FF921FB60000000);            { chunk A, exact }
  s2 := s1 - nd * DdBits($BE6777A5C0000000);            { chunk B, exact }
  t  := s2 - nd * DdBits($BCDEE59DA0000000);            { chunk C }
  { the residual of that last subtraction, plus the dd tail term — this is what
    keeps the answer right when x sits close to a multiple of pi/2 and s2 has
    cancelled away most of its bits }
  lo := (s2 - t) - nd * DdBits($BCDEE59DA0000000);
  lo := lo - nd * DdBits($3B298A2E03707345);
  r.Hi := t + lo;
  r.Lo := lo - (r.Hi - t);
  Result := Integer(n and 3);
end;

{ Same reduction, fast kernels. The reduction is what makes Sin(1e10) mean
  anything, so it is identical in both modes — only the kernel differs. }
procedure SinCosFast(x: Double; var s: TSinCos);
var r: TDd; a, b: Double; q: Integer;
begin
  if Abs(x) < 4.0e8 then
    q := FastTrigReduce(x, r)
  else
  begin
    { past the Cody-Waite chunks' range the reduction has to be the careful
      one — this is the path that makes Sin(1e10) mean anything, and it is the
      same code the exact mode uses }
    if Abs(x) >= 1.0e8 then q := TrigReduceBig(Abs(x), r)
    else q := TrigReduce(x, r);
  end;
  a := FastSinK(r.Hi, r.Lo);
  b := FastCosK(r.Hi, r.Lo);
  case q of
    0: begin s.Sn := a; s.Cs := b; end;
    1: begin s.Sn := b; s.Cs := -a; end;
    2: begin s.Sn := -a; s.Cs := -b; end;
  else begin s.Sn := -b; s.Cs := a; end;
  end;
end;

{ sin/cos/tan. The big-argument path reduces |x| and the caller reapplies the
  sign, because sin and tan are ODD and cos is EVEN — folding that into the
  reduction instead would need a second quadrant mapping. }
function Sin(x: Double): Double;
{$ifdef PXX_FLOAT_EXACT}
var sn, cs: TDd;
{$else}
var sc: TSinCos;
{$endif}
begin
  if x <> x then begin Result := x; Exit; end;                  { NaN }
  if x = 0.0 then begin Result := x; Exit; end;                 { keeps -0 }
  if (x - x) <> 0.0 then begin Result := (x - x) / (x - x); Exit; end;  { Inf -> NaN }
{$ifdef PXX_FLOAT_EXACT}
  SinCosDd(Abs(x), sn, cs);
  Result := sn.Hi + sn.Lo;
{$else}
  SinCosFast(Abs(x), sc);
  Result := sc.Sn;
{$endif}
  if x < 0.0 then Result := -Result;
end;
function Cos(x: Double): Double;
{$ifdef PXX_FLOAT_EXACT}
var sn, cs: TDd;
{$else}
var sc: TSinCos;
{$endif}
begin
  if x <> x then begin Result := x; Exit; end;
  if (x - x) <> 0.0 then begin Result := (x - x) / (x - x); Exit; end;
{$ifdef PXX_FLOAT_EXACT}
  SinCosDd(Abs(x), sn, cs);              { cos is even — no sign fixup }
  Result := cs.Hi + cs.Lo;
{$else}
  SinCosFast(Abs(x), sc);
  Result := sc.Cs;
{$endif}
end;

function Tan(x: Double): Double;
{$ifdef PXX_FLOAT_EXACT}
var sn, cs, t: TDd;
{$else}
var sc: TSinCos;
{$endif}
begin
  if x <> x then begin Result := x; Exit; end;
  if x = 0.0 then begin Result := x; Exit; end;                 { keeps -0 }
  if (x - x) <> 0.0 then begin Result := (x - x) / (x - x); Exit; end;
{$ifdef PXX_FLOAT_EXACT}
  { the QUOTIENT is formed in double-double, not from two rounded doubles:
    Sin(x)/Cos(x) rounds twice before dividing, and near an odd multiple of
    pi/2 the divisor's own error is what the answer is made of. }
  SinCosDd(Abs(x), sn, cs);
  t := DdDiv(sn, cs);
  Result := t.Hi + t.Lo;
{$else}
  SinCosFast(Abs(x), sc);
  Result := sc.Sn / sc.Cs;
{$endif}
  if x < 0.0 then Result := -Result;
end;

function ArcTan(x: Double): Double;
{ Over the double-double kernel, like Ln/Exp: the plain-double reduce-and-Taylor
  this replaces disagreed with libm on 2065 of 3005 random arguments (up to
  4 ulp). Sign is handled here so DdAtan only ever sees a non-negative
  argument. }
var ax: Double; t, w: TDd;
begin
  if x <> x then begin Result := x; Exit; end;              { NaN }
  ax := Abs(x);
  if ax > 1.7976931348623157e308 then                       { +-Inf -> +-pi/2 }
  begin
    w := DdPio2;
    Result := w.Hi + w.Lo;
    if x < 0.0 then Result := -Result;
    Exit;
  end;
  if ax = 0.0 then begin Result := x; Exit; end;            { keeps -0 }
  t.Hi := ax; t.Lo := 0.0;
  w := DdAtan(t);
  Result := w.Hi + w.Lo;
  if x < 0.0 then Result := -Result;
end;

{ asin/acos through the SAME identity as before — asin(x) = atan(x/sqrt(1-x^2))
  — but evaluated in double-double, which is the whole difference. The old
  plain-double form lost bits twice, in `1 - x*x` and again in the division,
  and measured 1977 of 3009 arguments wrong (up to 8 ulp).

  Two details carry most of the accuracy:

  - `1 - x^2` is formed as the EXACT product (1-x)(1+x) for |x| > 0.5. Near the
    endpoints `1 - x*x` cancels catastrophically; the factored form does not,
    because 1-x and 1+x are each exact there (Sterbenz).
  - acos is NOT `pi/2 - asin(x)`. That subtraction cancels for x near 1, where
    the answer is near zero: it measured up to **1099 ulp** out. acos gets its
    own atan(sqrt(1-x^2)/x) instead, so a small result is computed small rather
    than as the difference of two large ones. }
function ArcSin(x: Double): Double;
var ax: Double; p, sq, t, w: TDd;
begin
  if x <> x then begin Result := x; Exit; end;
  ax := Abs(x);
  if ax > 1.0 then begin Result := (x - x) / (x - x); Exit; end;   { NaN }
  if ax = 1.0 then
  begin
    w := DdPio2;
    Result := w.Hi + w.Lo;
    if x < 0.0 then Result := -Result;
    Exit;
  end;
  if x = 0.0 then begin Result := x; Exit; end;                    { keeps -0 }
  if ax <= 0.5 then
    p := DdAddD(DdMulD(Dd2Prod(ax, ax), -1.0), 1.0)                { 1 - x^2 }
  else
    p := DdMul(Dd2Sum(1.0, -ax), Dd2Sum(1.0, ax));                 { (1-x)(1+x) }
  sq := DdSqrt(p);
  t.Hi := ax; t.Lo := 0.0;
  w := DdAtan(DdDiv(t, sq));
  Result := w.Hi + w.Lo;
  if x < 0.0 then Result := -Result;
end;

function ArcCos(x: Double): Double;
var ax: Double; p, sq, w: TDd;
begin
  if x <> x then begin Result := x; Exit; end;
  ax := Abs(x);
  if ax > 1.0 then begin Result := (x - x) / (x - x); Exit; end;   { NaN }
  if x = 1.0 then begin Result := 0.0; Exit; end;
  if x = -1.0 then begin w := DdPi; Result := w.Hi + w.Lo; Exit; end;
  if x = 0.0 then begin w := DdPio2; Result := w.Hi + w.Lo; Exit; end;
  if ax <= 0.5 then
    p := DdAddD(DdMulD(Dd2Prod(ax, ax), -1.0), 1.0)
  else
    p := DdMul(Dd2Sum(1.0, -ax), Dd2Sum(1.0, ax));
  sq := DdSqrt(p);
  w := DdAtan(DdDiv(sq, Dd2Sum(ax, 0.0)));
  if x < 0.0 then w := DdAdd(DdPi, DdMulD(w, -1.0));
  Result := w.Hi + w.Lo;
end;

{ True for a NEGATIVE-signed double, INCLUDING -0.0 — which `x < 0.0` is not,
  and that difference is the whole of atan2's zero handling. }
function SignBitD(x: Double): Boolean;
begin
  Result := PSqrtInt64(@x)^ < 0;
end;

{ atan2 over the dd kernel. Two things changed from the old form:

  - The quotient y/x is formed as a DOUBLE-DOUBLE with its residual kept,
    instead of a rounded double handed to ArcTan. That single rounding, before
    the function even started, is what made this 1 ulp off glibc on 1409 of
    6000 random pairs while ArcTan itself was exact. pi is added as a dd for
    the same reason — `ArcTan(...) + 3.14159...` rounds twice.
  - The zero cases go by the SIGN BIT, not by `y < 0.0`. atan2 propagates a
    signed zero: atan2(-0, -1) is -pi and atan2(-0, 1) is -0, and `-0.0 < 0.0`
    is False, so the old code answered +pi and +0. Verified against FPC 3.2.2
    and CPython, which agree bit for bit on all eight zero combinations.

  This is also what unblocks NilPy's `math.atan2`, which compiler/pyparser.inc
  leaves undefined with a note citing atan2(0.5, 1) being a ulp out — that note
  is now stale, and the name is Track N's to add. }
function ArcTan2(y, x: Double): Double;
var q, w: TDd; sy, xneg: Boolean;
begin
  if (x <> x) or (y <> y) then begin Result := x + y; Exit; end;    { NaN }
  sy := SignBitD(y);
  { "x is on the negative side" — for a zero that is its sign BIT, not its
    value, because +0 and -0 send the answer to opposite sides of the axis. }
  if x = 0.0 then xneg := SignBitD(x) else xneg := x < 0.0;

  if y = 0.0 then
  begin
    if xneg then
    begin
      w := DdPi;
      Result := w.Hi + w.Lo;
    end
    else
      Result := 0.0;
    if sy then Result := -Result;
    Exit;
  end;
  if x = 0.0 then
  begin
    w := DdPio2;
    Result := w.Hi + w.Lo;
    if sy then Result := -Result;
    Exit;
  end;

  q := DdDivD(Dd2Sum(Abs(y), 0.0), Abs(x));   { |y|/|x| with the residual kept }
  w := DdAtan(q);
  if xneg then w := DdAdd(DdPi, DdMulD(w, -1.0));
  Result := w.Hi + w.Lo;
  if sy then Result := -Result;
end;

{ ================= expm1 / log1p, and the hyperbolic family =================

  All six hyperbolics were the textbook identity written out literally, and
  every one of them was wrong somewhere. Measured against glibc over 1,124
  arguments, 2026-08-15:

    ArcSinh(1e-15)  1.1102e-15  want 1e-15     11% WRONG
    ArcTanh(1e-15)  1.1102e-15  want 1e-15     11% WRONG
    Sinh(1e-15)     1.0547e-15  want 1e-15      5% WRONG
    ArcSinh(-94)    1497 ulp
    ArcCosh(0.5)    0.0         want NaN       domain error answered as a value
    Tanh(800)       NaN         want 1.0
    Tanh(+-Inf)     NaN         want +-1.0

  ONE cause, six symptoms: every formula routes a small answer through a
  quantity near 1, where the bits that ARE the answer fall off the bottom of the
  significand. `Exp(x) - 1` for small x keeps none of x; `Ln(1 + x)` the same.
  That is what expm1 and log1p exist for, and the RTL did not have them — so
  rather than patch six formulas, add the two primitives and let the formulas
  become the textbook ones AGAIN, just written around the cancellation.
  (devdocs/dev/normalise-dont-special-case.md: when several call sites are
  broken the same way, the fix belongs underneath them.)

  Neither primitive is EXPORTED, deliberately: `expm1` and `log1p` are libc
  names, and every name in this unit's interface is in scope for C name
  resolution because pxxcio does `uses math` — a Pascal `Expm1` would hijack
  libc's in every C program, exactly like the Pow/Log/CopySign trap documented
  at the top of this file. FPC's public spelling for log1p is `LnXP1`, which
  does NOT collide; adding it is a separate FPC-compat item, not this fix. }

function ExpM1(x: Double): Double;
{ e^x - 1. Kahan's construction: u = Exp(x) carries a relative error, and
  (u-1)/Ln(u) is exactly the factor that divides it back out — the same error
  sits in numerator and denominator. It needs an ACCURATE Ln, which is why this
  is cheap now and would not have been before the fast/exact log landed. }
var u: Double;
begin
  if x <> x then begin Result := x; Exit; end;                { NaN }
  if x >= 710.0 then begin Result := Exp(x); Exit; end;       { +Inf, no 1 to subtract }
  u := Exp(x);
  if u = 1.0 then begin Result := x; Exit; end;               { |x| < 2^-53: e^x-1 IS x }
  if u - 1.0 = -1.0 then begin Result := -1.0; Exit; end;     { x very negative }
  Result := (u - 1.0) * x / Ln(u);
end;

function LnP1(x: Double): Double;
{ ln(1+x), the same trick from the other side (Goldberg): 1+x rounds, and
  Ln(u)*x/(u-1) divides the rounding back out. }
var u: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x > 1.7976931348623157e308 then begin Result := x; Exit; end;   { +Inf }
  u := 1.0 + x;
  if u = 1.0 then begin Result := x; Exit; end;               { |x| < 2^-53 }
  Result := Ln(u) * x / (u - 1.0);
end;

function Sinh(x: Double): Double;
{ Two defects in `0.5*(Exp(x) - Exp(-x))`, and they are at opposite ends:
  small |x| cancels (both exponentials are ~1), and large |x| overflows EARLY —
  `0.5 * Exp(x)` evaluates Exp first, so it hits Inf around x = 709.8 even
  though sinh(710) = 1.1e308 is a perfectly ordinary double. Exp(x - ln2) is
  the same value with no intermediate to overflow.

  The small branch uses the identity in terms of t = e^|x| - 1:
    sinh = (t + t/(t+1)) / 2,  which for tiny t is (t + t)/2 = t. No subtraction. }
var ax, t, e: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x = 0.0 then begin Result := x; Exit; end;               { keeps -0 }
  ax := Abs(x);
  if ax > 709.0 then
    { NOT Exp(ax - ln2): at this magnitude ulp(ax) is 1.1e-13, so subtracting
      ln2 throws away low bits of the ARGUMENT, and exp turns that into 307 ulp
      of result. Halving the argument is exact (a power of two), so
      (0.5*w)*w = 0.5*e^ax costs two roundings instead. }
    e := (0.5 * Exp(0.5 * ax)) * Exp(0.5 * ax)
  else if ax < 22.0 then
  begin
    t := ExpM1(ax);
    e := 0.5 * (t + t / (t + 1.0));
  end
  else
    e := 0.5 * (Exp(ax) - Exp(-ax));
  if x < 0.0 then Result := -e else Result := e;
end;

function Cosh(x: Double): Double;
{ An ADDITION, so nothing cancels and the small end was always fine. Only the
  premature overflow needed fixing — same Exp(|x| - ln2) as Sinh. }
var ax: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  ax := Abs(x);
  if ax > 709.0 then
  begin
    { same split as Sinh — see the note there }
    Result := (0.5 * Exp(0.5 * ax)) * Exp(0.5 * ax);
    Exit;
  end;
  Result := 0.5 * (Exp(ax) + Exp(-ax));
end;

function Tanh(x: Double): Double;
{ `(e^x - e^-x) / (e^x + e^-x)` is Inf/Inf = NaN once Exp overflows, i.e. for
  |x| >= 710 — where the true value saturated to exactly +-1 some six hundred
  orders of magnitude earlier. It also cancels for small |x|.

  In terms of t = e^(-2|x|) - 1:  tanh = -t / (t + 2), which for tiny |x| is
  2|x|/2 = |x|. Above |x| = 22, e^-44 is below half an ulp of 1, so the answer
  IS 1.0 and saying so directly is both faster and exactly right. }
var ax, t, r: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x = 0.0 then begin Result := x; Exit; end;               { keeps -0 }
  ax := Abs(x);
  if ax >= 22.0 then r := 1.0
  else if ax >= 1.0 then
    r := 1.0 - 2.0 / (Exp(2.0 * ax) + 1.0)
  else
  begin
    t := ExpM1(-2.0 * ax);
    r := -t / (t + 2.0);
  end;
  if x < 0.0 then Result := -r else Result := r;
end;

function ArcSinh(x: Double): Double;
{ `Ln(x + Sqrt(x*x + 1))` has THREE defects:
  - x negative: x + sqrt(x^2+1) cancels — 1497 ulp at x = -94. Folding the sign
    out first (asinh is odd) removes it entirely.
  - |x| small: the argument is ~1 and Ln near 1 keeps none of the answer.
    ArcSinh(1e-15) returned 1.1102e-15, which is 11% wrong.
  - |x| > 1.3e154: x*x overflows and the result becomes Inf, where
    asinh(1e200) = 461.2 is an ordinary number.
  Three ranges, three algebraically identical forms, each stable where it is
  used. }
var ax, r: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x = 0.0 then begin Result := x; Exit; end;               { keeps -0 }
  ax := Abs(x);
  if ax > 1.0e153 then
    r := Ln(ax) + 0.6931471805599453                          { asinh ~ ln(2x) }
  else if ax > 2.0 then
    { x + sqrt(x^2+1) rewritten as 2x + 1/(sqrt(x^2+1) + x): same value, no
      large-minus-large }
    r := Ln(2.0 * ax + 1.0 / (Sqrt(ax * ax + 1.0) + ax))
  else
    r := LnP1(ax + ax * ax / (1.0 + Sqrt(ax * ax + 1.0)));
  if x < 0.0 then Result := -r else Result := r;
end;

function ArcCosh(x: Double): Double;
{ x < 1 is a DOMAIN ERROR and this returned 0.0 — a value the caller cannot
  distinguish from the true answer at x = 1. glibc, CPython and FPC all give
  NaN, and so does this now. The x^2 overflow and the near-1 cancellation get
  the same treatment as ArcSinh. }
var t, z: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x < 1.0 then begin z := 0.0; Result := z / z; Exit; end; { NaN, was 0.0 }
  if x > 1.0e153 then begin Result := Ln(x) + 0.6931471805599453; Exit; end;
  if x > 2.0 then
  begin
    Result := Ln(2.0 * x - 1.0 / (x + Sqrt(x * x - 1.0)));
    Exit;
  end;
  t := x - 1.0;                                               { Sterbenz-exact here }
  Result := LnP1(t + Sqrt(2.0 * t + t * t));
end;

function ArcTanh(x: Double): Double;
{ `0.5*Ln((1+x)/(1-x))` forms a quotient that is ~1 for small x, so Ln throws
  away exactly the bits that are the answer: ArcTanh(1e-15) returned
  1.1102e-15, 11% wrong. 0.5*ln1p(2x/(1-x)) is the same expression with the
  1 taken out by hand. }
var ax, r, z: Double;
begin
  if x <> x then begin Result := x; Exit; end;
  if x = 0.0 then begin Result := x; Exit; end;               { keeps -0 }
  ax := Abs(x);
  if ax > 1.0 then begin z := 0.0; Result := z / z; Exit; end;        { NaN }
  if ax = 1.0 then
  begin
    z := 0.0;
    if x < 0.0 then Result := -1.0 / z else Result := 1.0 / z;        { -+Inf }
    Exit;
  end;
  r := 0.5 * LnP1(2.0 * ax / (1.0 - ax));
  if x < 0.0 then Result := -r else Result := r;
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
var z: Double;
{$ifdef PXX_FLOAT_EXACT}
    r, c: TDd;
{$endif}
begin
  if x <> x then begin Result := x; Exit; end;
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
  if x = 0.0 then begin z := 0.0; Result := -1.0 / z; Exit; end;
  if x > 1.7976931348623157e308 then begin Result := x; Exit; end;
{$ifdef PXX_FLOAT_EXACT}
  c.Hi := DdBits($3FDBCB7B1526E50E);        { 1/ln10 }
  c.Lo := DdBits($3C695355BAAAFAD3);
  r := DdMul(DdLogD(x), c);
  Result := r.Hi + r.Lo;
{$else}
  { NOT FastLnBits(x) * (1/ln10): that rounds twice and loses the property
    people actually look at, Log10 of a power of ten being an exact integer.
    Splitting the exponent out first keeps the integer part exact and confines
    the approximation to the mantissa. }
  Result := FastLog10D(x);
{$endif}
end;

function Log2(x: Double): Double;
var z: Double;
{$ifdef PXX_FLOAT_EXACT}
    r, c: TDd;
{$endif}
begin
  if x <> x then begin Result := x; Exit; end;
  if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
  if x = 0.0 then begin z := 0.0; Result := -1.0 / z; Exit; end;
  if x > 1.7976931348623157e308 then begin Result := x; Exit; end;
{$ifdef PXX_FLOAT_EXACT}
  c.Hi := DdBits($3FF71547652B82FE);        { 1/ln2 }
  c.Lo := DdBits($3C7777D0FFDA0D24);
  r := DdMul(DdLogD(x), c);
  Result := r.Hi + r.Lo;
{$else}
  Result := FastLog2D(x);
{$endif}
end;

function LogN(base, x: Double): Double;
{ NOTE the argument order — base FIRST, as in FPC. Python's math.log(x, base) is
  the other way round, which is why NilPy needs its own intercept rather than
  binding to this (bug-n-math-trunc-and-log-need-frontend-intercepts). }
var r: TDd;
begin
  if (x <> x) or (base <> base) then begin Result := x + base; Exit; end;
  if (x <= 0.0) or (base <= 0.0) or (base = 1.0) then
  begin
    { same IEEE edges as Ln, computed rather than special-cased }
    Result := Ln(x) / Ln(base);
    Exit;
  end;
  { STAYS double-double in both modes, deliberately. Log10 and Log2 can be both
    fast and exact because the exponent extraction hands them the integer part
    for free; an arbitrary base has no such trick, so LogN is a genuine QUOTIENT
    of two logarithms and each rounding lands directly in the answer.
    FastLnBits(x) / FastLnBits(base) measured LogN(10,1000) = 2.9999999999999996
    and LogN(3,81) = 4.0000000000000009 — test/lib_log_exactness.pas asserts both
    of those are integers, and it is right to.

    The way out is a fast hi/lo log, which Power needs for the same reason:
    [[feature-b-rtl-fast-power-needs-a-hi-lo-log]]. Until then, correctness wins
    over speed here — LogN is not an inner-loop function the way Ln/Exp are. }
  r := DdDiv(DdLogD(x), DdLogD(base));
  Result := r.Hi + r.Lo;
end;

function Hypot(x, y: Double): Double;
{ `Sqrt(x*x + y*y)` squares before it adds, so it dies at both ends of the
  range on values the ANSWER can represent perfectly well:

    Hypot(3e300, 4e300)   was Inf   want 5e300     x*x overflowed
    Hypot(3e-200, 4e-200) was 0     want 5e-200    x*x underflowed to zero

  Scaling by the larger operand fixes both at once: t = small/large is in
  [0, 1], so 1 + t*t is in [1, 2] and cannot overflow or underflow, and the one
  multiply by `large` at the end puts the magnitude back. Same cancellation
  family as the hyperbolics — an intermediate leaving the representable range
  while the result never does. }
var ax, ay, t: Double;
begin
  ax := Abs(x);
  ay := Abs(y);
  { IEEE 754: hypot(+-Inf, anything) is +Inf, INCLUDING hypot(Inf, NaN) — the
    infinity wins over the NaN. Test it before the NaN check for that reason. }
  if (ax > 1.7976931348623157e308) or (ay > 1.7976931348623157e308) then
  begin
    Result := 1.7976931348623157e308 * 2.0;
    Exit;
  end;
  if (x <> x) or (y <> y) then begin Result := x + y; Exit; end;   { NaN }
  if ay > ax then begin t := ax; ax := ay; ay := t; end;
  if ax = 0.0 then begin Result := 0.0; Exit; end;
  { Scaled in ALL ranges, not only where x*x would overflow — measured, against
    the intuition. Adding a direct `Sqrt(ax*ax + ay*ay)` fast path for the safe
    band (two roundings instead of three) made accuracy WORSE, not better:
    against CPython on 148 arguments the scaled form matches 94.6% and the
    direct one 85.1%. `1 + t*t` with t in [0,1] has an exact leading 1 and a
    summand no larger, so it loses less than squaring two arbitrary magnitudes
    does.

    FPC matches CPython 100% here, but not by being cleverer: its `float` is
    80-bit Extended on x86, so `sqrt(x*x + y*y)` accumulates in 64 bits of
    mantissa and rounds once at the end. We have no Extended (it is aliased to
    Double), so matching that would need error-compensated arithmetic — the dd
    path — which is exactly the cost the float policy declines to pay by
    default. 1 ulp is the contract here. }
  t := ay / ax;
  Result := ax * Sqrt(1.0 + t * t);
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
  { the LOG stays double-double even in fast mode, and that is deliberate:
    y*log(x) is multiplied by the exponent before exp() sees it, so an error in
    log(x) is AMPLIFIED by |y|. Power(1.0000001, 1e7) would lose most of its
    significance to a 1-ulp log. Only the final exp is the fast one. }
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
{ Truncated remainder, sign of x. `x - Int(x/y)*y` was wrong twice over:

  - `Int` of a large double is INT64_MIN on x86-64 and saturates on the 32-bit
    targets ([[bug-a-int-of-a-large-double-is-int64-min-on-x86-64]]), so
    FMod(1e300, 3.0) returned 1e300 — the INPUT, entirely unreduced, where the
    answer is 0.
  - even with a correct Int, x/y ROUNDS, and multiplying the rounded quotient
    back by y cannot recover the remainder once the ratio exceeds 2^53.

  fmod is one of the few libm functions whose result is EXACTLY defined — no
  rounding is permitted — so an approximate formula is the wrong shape entirely.
  This is the scaled repeated subtraction, in which every step is exact:
  the invariant is ax < 2*d, so a subtraction only ever happens when
  d <= ax < 2*d, and Sterbenz's lemma makes `ax - d` exact there. Halving d is
  exact because it is a power-of-two scale. Therefore so is the result.

  The loop runs once per binade between |x| and |y| — about 1000 iterations in
  the extreme FMod(1e300, 3.0) case, a handful in every ordinary one. }
var ax, ay, d: Double; n, i: Integer;
begin
  if (x <> x) or (y <> y) then begin Result := x + y; Exit; end;      { NaN }
  ay := Abs(y);
  if ay = 0.0 then begin Result := 0.0; Exit; end;                    { FPC: 0, not NaN }
  ax := Abs(x);
  if ax > 1.7976931348623157e308 then begin Result := ax - ax; Exit; end;  { Inf -> NaN }
  if ay > 1.7976931348623157e308 then begin Result := x; Exit; end;   { y = Inf }
  if ax < ay then begin Result := x; Exit; end;
  if ax = ay then
  begin
    if x < 0.0 then Result := -0.0 else Result := 0.0;
    Exit;
  end;
  { scale ay up while it stays at or below ax — d never exceeds ax, so the
    doubling cannot overflow no matter how large ax is }
  d := ay;
  n := 0;
  while d <= ax * 0.5 do
  begin
    d := d * 2.0;
    n := n + 1;
  end;
  for i := n downto 0 do
  begin
    if ax >= d then ax := ax - d;      { exact: d <= ax < 2*d }
    d := d * 0.5;
  end;
  if x < 0.0 then Result := -ax else Result := ax;
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

{ The conversion FACTOR is formed first and then multiplied — CPython and FPC
  both associate it that way, and `x * 180 / pi` differs from `x * (180 / pi)`
  in the last bit: math.degrees(3.14) answered 179.90874767107852 where both
  references say 179.9087476710785.
  bug-nilpy-math-surface-remaining-gaps-and-degrees-association }
function DegToRad(d: Double): Double;
begin
  Result := d * (3.14159265358979323846 / 180.0);
end;

function RadToDeg(r: Double): Double;
begin
  Result := r * (180.0 / 3.14159265358979323846);
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
