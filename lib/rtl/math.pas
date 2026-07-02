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
function Floor(x: Double): Double;
function Ceil(x: Double): Double;
function FMod(x, y: Double): Double;
function Sign(x: Double): Integer;
function Min(a, b: Double): Double;
function Max(a, b: Double): Double;
function DegToRad(d: Double): Double;
function RadToDeg(r: Double): Double;

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
function Floor(x: Single): Single;
function Ceil(x: Single): Single;

implementation

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
{ Newton-Raphson: g := (g + x/g)/2, quadratic convergence. }
var g, ng: Double; i: Integer;
begin
  if x <= 0.0 then begin Result := 0.0; Exit; end;
  g := x;
  if g < 1.0 then g := 1.0;
  for i := 1 to 200 do
  begin
    ng := 0.5 * (g + x / g);
    if ng = g then break;
    g := ng;
  end;
  Result := g;
end;

function Exp(x: Double): Double;
{ e^x = 2^k * e^r, r = x - k*ln2, Taylor for e^r. Scale in a LOCAL (res). }
var term, sum, r, res: Double; k, kc, i: Integer;
begin
  k := Trunc(x / 0.69314718055994530942);
  r := x - k * 0.69314718055994530942;
  term := 1.0; sum := 1.0;
  for i := 1 to 40 do
  begin
    term := term * r / i;
    sum := sum + term;
  end;
  res := sum;
  kc := k;
  while kc > 0 do begin res := res * 2.0; kc := kc - 1; end;
  while kc < 0 do begin res := res / 2.0; kc := kc + 1; end;
  Result := res;
end;

function Ln(x: Double): Double;
{ x = m*2^e, m in [1,2); ln(m) via atanh series t=(m-1)/(m+1). }
var m, t, term, sum, p: Double; e, i: Integer;
begin
  if x <= 0.0 then begin Result := 0.0; Exit; end;
  e := 0;
  m := x;
  while m >= 2.0 do begin m := m / 2.0; e := e + 1; end;
  while m < 1.0 do begin m := m * 2.0; e := e - 1; end;
  t := (m - 1.0) / (m + 1.0);
  p := t * t;
  term := t;
  sum := 0.0;
  i := 1;
  while i <= 99 do
  begin
    sum := sum + term / i;
    term := term * p;
    i := i + 2;
  end;
  Result := 2.0 * sum + e * 0.69314718055994530942;
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

function Log10(x: Double): Double;
begin
  Result := Ln(x) / 2.30258509299404568402;
end;

function Log2(x: Double): Double;
begin
  Result := Ln(x) / 0.69314718055994530942;
end;

function LogN(base, x: Double): Double;
begin
  Result := Ln(x) / Ln(base);
end;

function Hypot(x, y: Double): Double;
begin
  Result := Sqrt(x * x + y * y);
end;

function Power(base, exponent: Double): Double;
{ base^exponent = exp(exponent * ln(base)), base > 0. }
begin
  if base <= 0.0 then begin Result := 0.0; Exit; end;
  Result := Exp(exponent * Ln(base));
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

function Floor(x: Double): Double;
begin
  if (x < 0.0) and (Frac(x) <> 0.0) then Result := Int(x) - 1.0
  else Result := Int(x);
end;

function Ceil(x: Double): Double;
begin
  if (x > 0.0) and (Frac(x) <> 0.0) then Result := Int(x) + 1.0
  else Result := Int(x);
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

function Floor(x: Single): Single;
var d: Double;
begin
  d := x;
  Result := Floor(d);
end;

function Ceil(x: Single): Single;
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
