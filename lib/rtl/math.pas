unit math;
interface
uses math_ext;

function Min(a, b: Integer): Integer;
function Max(a, b: Integer): Integer;
function Power(base, exponent: Integer): Integer;
function Gcd(a, b: Integer): Integer;
function Lcm(a, b: Integer): Integer;

{ Floating-point transcendentals — pure Pascal, no libm (keeps the no-libc
  design). All numeric constants are float literals: a plain integer literal
  assigned/initialised into a Double currently misses the int->float conversion
  (feature-int-to-float-assign), so `0.0`/`2.0` etc. are used throughout (0 is
  bit-identical and safe). }
function Pi: Double;
function Abs(x: Double): Double;
function Sqrt(x: Double): Double;
function Exp(x: Double): Double;
function Ln(x: Double): Double;
function Sin(x: Double): Double;
function Cos(x: Double): Double;
function ArcTan(x: Double): Double;
function Power(base, exponent: Double): Double;

implementation

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
{ e^x = 2^k * e^r, r = x - k*ln2, Taylor for e^r. Scale in a LOCAL (res): a
  function Result read-modified inside a loop is miscompiled to 0 (pre-existing
  bug feature-result-in-loop), so never touch Result in the while loops. }
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

function ArcTan(x: Double): Double;
{ Halve the argument via atan(r)=2*atan(r/(1+sqrt(1+r^2))) until |r| is small, so
  the Taylor series converges fast (the raw series stalls near |r|=1, e.g.
  atan(1)). Then undo the halvings by doubling. Scaling is in a LOCAL (never
  Result in a loop — feature-result-in-loop). }
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

function Power(base, exponent: Double): Double;
{ base^exponent = exp(exponent * ln(base)), base > 0. }
begin
  if base <= 0.0 then begin Result := 0.0; Exit; end;
  Result := Exp(exponent * Ln(base));
end;

function Min(a, b: Integer): Integer;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Integer): Integer;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;

function Power(base, exponent: Integer): Integer;
var
  i, res: Integer;
begin
  res := 1;
  for i := 1 to exponent do
    res := res * base;
  Result := res;
end;

function Gcd(a, b: Integer): Integer;
var
  temp, x, y: Integer;
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
  if (a = 0) or (b = 0) then
    Result := 0
  else
    Result := (a * b) div Gcd(a, b);
end;

end.
