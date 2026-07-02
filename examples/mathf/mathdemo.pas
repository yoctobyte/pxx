{ SPDX-License-Identifier: 0BSD }
program MathDemo;
{ Oracle + showcase for the float math library (Track B).

  Two jobs:
  - exercise lib/rtl/math.pas (Double + Single overloads) against known values,
  - probe the float foundations: Single->Double conversion, mixed-type promotion,
    and the `real` type.

  Floats are not guaranteed byte-identical across targets, so the gate is
  TOLERANCE-based: each check prints PASS/FAIL and the run ends 'ALL OK' iff all
  pass. Displayed numbers use fixed-decimal (`:0:n`) formatting, which keeps the
  human-readable part stable; the ALL OK line is what `make lib-test` asserts. }

uses math, sysutils;

const
  EPS  = 0.000000001;     { 1e-9  for Double checks }
  EPSS = 0.00001;         { 1e-5  for Single checks }

var
  ok: Boolean;
  s: Single;
  d: Double;
  r: Real;
  acc, h, xx: Double;
  i, n: Integer;

function Approx(a, b, eps: Double): Boolean;
begin
  Approx := Abs(a - b) < eps;
end;

procedure Chk(const name: AnsiString; got, want: Double);
begin
  if Approx(got, want, EPS) then
    writeln('  ok   ', name, ' = ', got:0:9)
  else
  begin
    ok := False;
    writeln('  FAIL ', name, ' = ', got:0:9, '  want ', want:0:9);
  end;
end;

procedure ChkS(const name: AnsiString; got, want: Single);
begin
  if Approx(got, want, EPSS) then
    writeln('  ok   ', name, ' = ', got:0:6)
  else
  begin
    ok := False;
    writeln('  FAIL ', name, ' = ', got:0:6, '  want ', want:0:6);
  end;
end;

{ overloaded discriminator: what static type does an expression resolve to? }
function TypeName(x: Single): AnsiString;
begin
  TypeName := 'single';
end;

function TypeName(x: Double): AnsiString;
begin
  TypeName := 'double';
end;

procedure ChkStr(const name, got, want: AnsiString);
begin
  if got = want then writeln('  ok   ', name, ' = ', got)
  else begin ok := False; writeln('  FAIL ', name, ' = ', got, '  want ', want); end;
end;

begin
  ok := True;

  writeln('-- Double transcendentals --');
  Chk('sqrt(2)',      Sqrt(2.0),        1.41421356237309515);
  Chk('exp(1)',       Exp(1.0),         2.71828182845904509);
  Chk('ln(e)',        Ln(2.71828182845904509), 1.0);
  Chk('sin(pi/6)',    Sin(Pi / 6.0),    0.5);
  Chk('cos(pi/3)',    Cos(Pi / 3.0),    0.5);
  Chk('tan(pi/4)',    Tan(Pi / 4.0),    1.0);
  Chk('arcsin(0.5)',  ArcSin(0.5),      Pi / 6.0);
  Chk('arccos(0.5)',  ArcCos(0.5),      Pi / 3.0);
  Chk('arctan(1)',    ArcTan(1.0),      Pi / 4.0);
  Chk('arctan2(1,1)', ArcTan2(1.0, 1.0), Pi / 4.0);
  Chk('arctan2(1,-1)',ArcTan2(1.0, -1.0), 3.0 * Pi / 4.0);
  Chk('log10(1000)',  Log10(1000.0),    3.0);
  Chk('log2(1024)',   Log2(1024.0),     10.0);
  Chk('logN(3,81)',   LogN(3.0, 81.0),  4.0);
  Chk('hypot(3,4)',   Hypot(3.0, 4.0),  5.0);
  Chk('power(2,0.5)', Power(2.0, 0.5),  1.41421356237309515);
  Chk('intpower(2,10)', IntPower(2.0, 10), 1024.0);
  Chk('intpower(2,-2)', IntPower(2.0, -2), 0.25);

  writeln('-- hyperbolic --');
  Chk('sinh(1)',      Sinh(1.0),        1.17520119364380137);
  Chk('cosh(1)',      Cosh(1.0),        1.54308063481524371);
  Chk('tanh(1)',      Tanh(1.0),        0.76159415595576485);
  Chk('arcsinh(sinh1)', ArcSinh(Sinh(1.0)), 1.0);
  Chk('arccosh(cosh1)', ArcCosh(Cosh(1.0)), 1.0);
  Chk('arctanh(tanh1)', ArcTanh(Tanh(1.0)), 1.0);

  writeln('-- rounding / misc --');
  Chk('floor(-2.3)',  Floor(-2.3),      -3.0);
  Chk('ceil(-2.3)',   Ceil(-2.3),       -2.0);
  Chk('floor(2.7)',   Floor(2.7),       2.0);
  Chk('ceil(2.1)',    Ceil(2.1),        3.0);
  Chk('fmod(7,3)',    FMod(7.0, 3.0),   1.0);
  Chk('fmod(-7,3)',   FMod(-7.0, 3.0),  -1.0);
  Chk('degtorad(180)',DegToRad(180.0),  Pi);
  Chk('radtodeg(pi)', RadToDeg(Pi),     180.0);
  Chk('min(3,5)',     Min(3.0, 5.0),    3.0);
  Chk('max(3,5)',     Max(3.0, 5.0),    5.0);
  { Abs must stay integer-valued even with the math unit in scope (the float
    Abs overloads here must not shadow the integer/int64 intrinsic). }
  ChkStr('abs(-7):int',     IntToStr(Abs(-7)),                  '7');
  ChkStr('abs(int64):i64',  IntToStr(Abs(Int64(-5000000000))),  '5000000000');

  writeln('-- identities --');
  Chk('sin^2+cos^2',  Sin(0.7) * Sin(0.7) + Cos(0.7) * Cos(0.7), 1.0);
  Chk('exp(ln 5)',    Exp(Ln(5.0)),     5.0);
  Chk('sign tests',   Sign(-3.5) + Sign(0.0) + Sign(2.0), 0.0);

  writeln('-- Single overloads (narrowed) --');
  ChkS('sqrt(2):single',    Sqrt(Single(2.0)),  1.41421356);
  ChkS('sin(pi/6):single',  Sin(Single(Pi / 6.0)), 0.5);
  ChkS('exp(1):single',     Exp(Single(1.0)),   2.71828183);
  ChkS('log2(8):single',    Log2(Single(8.0)),  3.0);
  ChkS('hypot(3,4):single', Hypot(Single(3.0), Single(4.0)), 5.0);

  writeln('-- Single->Double conversion + promotion --');
  s := 1.5;
  d := s;                                  { widen }
  Chk('s->d widen', d, 1.5);
  s := 0.5;
  d := 2.0;
  ChkStr('typeof(d)',   TypeName(d),     'double');
  ChkStr('typeof(s)',   TypeName(s),     'single');
  ChkStr('typeof(s*d)', TypeName(s * d), 'double');   { mixed promotes }
  ChkStr('typeof(s+d)', TypeName(s + d), 'double');
  Chk('value s*d', s * d, 1.0);

  writeln('-- real type (aliased to Double) --');
  r := Pi;
  Chk('real = double (sin)', Sin(r), Sin(Pi));
  r := 2.0;
  Chk('real arithmetic', r * r + 1.0, 5.0);

  writeln('-- numerical showcase --');
  { pi via Leibniz-ish Machin: pi = 16*atan(1/5) - 4*atan(1/239) }
  Chk('pi (Machin)', 16.0 * ArcTan(1.0 / 5.0) - 4.0 * ArcTan(1.0 / 239.0), Pi);
  { e via series sum 1/k! }
  acc := 1.0; xx := 1.0;
  for i := 1 to 20 do begin xx := xx / i; acc := acc + xx; end;
  Chk('e (series)', acc, 2.71828182845904509);
  { Simpson integral of sin x over [0,pi] = 2 }
  n := 1000; h := Pi / n; acc := Sin(0.0) + Sin(Pi);
  for i := 1 to n - 1 do
  begin
    xx := i * h;
    if (i and 1) = 1 then acc := acc + 4.0 * Sin(xx)
    else acc := acc + 2.0 * Sin(xx);
  end;
  acc := acc * h / 3.0;
  Chk('simpson sin[0,pi]', acc, 2.0);
  { Newton root of x^2-2 -> sqrt(2) }
  xx := 1.0;
  for i := 1 to 30 do xx := 0.5 * (xx + 2.0 / xx);
  Chk('newton sqrt2', xx, 1.41421356237309515);

  writeln;
  if ok then writeln('ALL OK') else writeln('FAILURES');
end.
