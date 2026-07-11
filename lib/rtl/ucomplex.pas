unit ucomplex;

{ Complex numbers, API-compatible with FPC rtl-extra ucomplex where the pxx
  dialect allows. Ported from FPC 3.2.2 (Pierre Muller, LGPL with linking
  exception); math via the own-RTL math unit (FP-determinism: no libm).

  pxx-vs-FPC deltas (documented, not silently different):
  - No `operator :=` (implicit Double->complex conversion). Use cinit(r, 0.0).
  - Operator overload dispatch keys on (op, record type) only — one overload
    per op per type — so FPC's mixed (complex, real) / (real, complex) operator
    forms are NOT declarable; registering them would shadow-collide with the
    (complex, complex) forms. Mixed arithmetic: z + cinit(r, 0.0), or the
    function forms below.
  - No unary `operator -`: use cneg(z).
  - No `operator **`: use cpow(z1, z2) / cpowr(z, r).
  - `<>` is not derived from `=`: use `not (a = b)` for inequality. }

interface

uses math;

type
  complex = record
    re: Double;
    im: Double;
  end;
  pcomplex = ^complex;

const
  i:  complex = (re: 0.0; im: 1.0);
  _0: complex = (re: 0.0; im: 0.0);

{ four base operations and comparison — (complex, complex) forms only }
operator + (z1, z2: complex) z: complex;
operator - (z1, z2: complex) z: complex;
operator * (z1, z2: complex) z: complex;
operator / (znum, zden: complex) z: complex;
operator = (z1, z2: complex) b: Boolean;

function cinit(_re, _im: Double): complex;
function csamevalue(z1, z2: complex): Boolean;

{ mixed complex/Double function forms (pxx: not declarable as operators) }
function caddr(z1: complex; r: Double): complex;   { z1 + r }
function csubr(z1: complex; r: Double): complex;   { z1 - r }
function crsub(r: Double; z1: complex): complex;   { r - z1 }
function cmulr(z1: complex; r: Double): complex;   { z1 * r }
function cdivr(znum: complex; r: Double): complex; { znum / r }
function crdiv(r: Double; zden: complex): complex; { r / zden }
function cneg(z: complex): complex;                { -z }
function cdiv(znum, zden: complex): complex;       { function form of / }

{ complex functions }
function cong(z: complex): complex;       { conjugate }
function cinv(z: complex): complex;       { 1/z }

{ complex functions with real return values }
function cmod(z: complex): Double;        { modulus }
function carg(z: complex): Double;        { argument: z = |z|.e^(i.arg) }

{ elementary functions }
function cexp(z: complex): complex;       { exponential }
function cln(z: complex): complex;        { natural logarithm }
function csqr(z: complex): complex;       { square }
function csqrt(z: complex): complex;      { square root }
function cpow(z1, z2: complex): complex;  { z1 ** z2 }
function cpowr(z1: complex; r: Double): complex; { z1 ** r }

{ trigonometric functions }
function ccos(z: complex): complex;
function csin(z: complex): complex;
function ctg(z: complex): complex;

{ inverse trigonometric functions }
function carc_cos(z: complex): complex;
function carc_sin(z: complex): complex;
function carc_tg(z: complex): complex;

{ hyperbolic functions }
function cch(z: complex): complex;
function csh(z: complex): complex;
function cth(z: complex): complex;

{ inverse hyperbolic functions }
function carg_ch(z: complex): complex;
function carg_sh(z: complex): complex;
function carg_th(z: complex): complex;

{ write out a complex value }
function cstr(z: complex): string;
function cstr(z: complex; len: Integer): string;
function cstr(z: complex; len, dec: Integer): string;

implementation

operator + (z1, z2: complex) z: complex;
begin
  z.re := z1.re + z2.re;
  z.im := z1.im + z2.im;
end;

operator - (z1, z2: complex) z: complex;
begin
  z.re := z1.re - z2.re;
  z.im := z1.im - z2.im;
end;

operator * (z1, z2: complex) z: complex;
begin
  z.re := (z1.re * z2.re) - (z1.im * z2.im);
  z.im := (z1.re * z2.im) + (z1.im * z2.re);
end;

operator / (znum, zden: complex) z: complex;
{ Smith's algorithm: scale by the larger denominator component so the
  denominator square cannot overflow prematurely. }
var
  tmp, denom: Double;
begin
  if Abs(zden.re) > Abs(zden.im) then
  begin
    tmp := zden.im / zden.re;
    denom := zden.re + zden.im * tmp;
    z.re := (znum.re + znum.im * tmp) / denom;
    z.im := (znum.im - znum.re * tmp) / denom;
  end
  else
  begin
    tmp := zden.re / zden.im;
    denom := zden.im + zden.re * tmp;
    z.re := (znum.im + znum.re * tmp) / denom;
    z.im := (-znum.re + znum.im * tmp) / denom;
  end;
end;

operator = (z1, z2: complex) b: Boolean;
begin
  b := (z1.re = z2.re) and (z1.im = z2.im);
end;

function cinit(_re, _im: Double): complex;
begin
  Result.re := _re;
  Result.im := _im;
end;

function csamevalue(z1, z2: complex): Boolean;
{ FPC SameValue semantics with the default Double resolution 1E-12. }
  function Same(a, b: Double): Boolean;
  var eps: Double;
  begin
    eps := Abs(a);
    if Abs(b) < eps then eps := Abs(b);
    eps := eps * 1E-12;
    if eps < 1E-12 then eps := 1E-12;
    Result := Abs(a - b) <= eps;
  end;
begin
  Result := Same(z1.re, z2.re) and Same(z1.im, z2.im);
end;

function caddr(z1: complex; r: Double): complex;
begin
  Result.re := z1.re + r;
  Result.im := z1.im;
end;

function csubr(z1: complex; r: Double): complex;
begin
  Result.re := z1.re - r;
  Result.im := z1.im;
end;

function crsub(r: Double; z1: complex): complex;
begin
  Result.re := r - z1.re;
  Result.im := -z1.im;
end;

function cmulr(z1: complex; r: Double): complex;
begin
  Result.re := z1.re * r;
  Result.im := z1.im * r;
end;

function cdivr(znum: complex; r: Double): complex;
begin
  Result.re := znum.re / r;
  Result.im := znum.im / r;
end;

function crdiv(r: Double; zden: complex): complex;
var denom: Double;
begin
  denom := (zden.re * zden.re) + (zden.im * zden.im);
  Result.re := (r * zden.re) / denom;
  Result.im := -(r * zden.im) / denom;
end;

function cneg(z: complex): complex;
begin
  Result.re := -z.re;
  Result.im := -z.im;
end;

function cdiv(znum, zden: complex): complex;
begin
  Result := znum / zden;
end;

function cong(z: complex): complex;
begin
  Result.re := z.re;
  Result.im := -z.im;
end;

function cinv(z: complex): complex;
var denom: Double;
begin
  denom := (z.re * z.re) + (z.im * z.im);
  Result.re := z.re / denom;
  Result.im := -z.im / denom;
end;

function cmod(z: complex): Double;
begin
  Result := Sqrt((z.re * z.re) + (z.im * z.im));
end;

function carg(z: complex): Double;
begin
  Result := ArcTan2(z.im, z.re);
end;

function cexp(z: complex): complex;
var expz: Double;
begin
  expz := Exp(z.re);
  Result.re := expz * Cos(z.im);
  Result.im := expz * Sin(z.im);
end;

function cln(z: complex): complex;
begin
  Result.re := Ln(cmod(z));
  Result.im := ArcTan2(z.im, z.re);
end;

function csqr(z: complex): complex;
begin
  Result.re := z.re * z.re - z.im * z.im;
  Result.im := 2.0 * z.re * z.im;
end;

function csqrt(z: complex): complex;
var root, q: Double;
begin
  if (z.re <> 0.0) or (z.im <> 0.0) then
  begin
    root := Sqrt(0.5 * (Abs(z.re) + cmod(z)));
    q := z.im / (2.0 * root);
    if z.re >= 0.0 then
    begin
      Result.re := root;
      Result.im := q;
    end
    else if z.im < 0.0 then
    begin
      Result.re := -q;
      Result.im := -root;
    end
    else
    begin
      Result.re := q;
      Result.im := root;
    end;
  end
  else
    Result := z;
end;

function cpow(z1, z2: complex): complex;
begin
  Result := cexp(z2 * cln(z1));
end;

function cpowr(z1: complex; r: Double): complex;
begin
  Result := cexp(cmulr(cln(z1), r));
end;

function ccos(z: complex): complex;
begin
  Result.re := Cos(z.re) * Cosh(z.im);
  Result.im := -Sin(z.re) * Sinh(z.im);
end;

function csin(z: complex): complex;
begin
  Result.re := Sin(z.re) * Cosh(z.im);
  Result.im := Cos(z.re) * Sinh(z.im);
end;

function ctg(z: complex): complex;
begin
  Result := csin(z) / ccos(z);
end;

function carc_cos(z: complex): complex;
{ arccos(z) = -i.argch(z) }
begin
  Result := cneg(i) * carg_ch(z);
end;

function carc_sin(z: complex): complex;
{ arcsin(z) = -i.argsh(i.z) }
begin
  Result := cneg(i) * carg_sh(i * z);
end;

function carc_tg(z: complex): complex;
{ arctg(z) = -i.argth(i.z) }
begin
  Result := cneg(i) * carg_th(i * z);
end;

function cch(z: complex): complex;
begin
  Result.re := Cosh(z.re) * Cos(z.im);
  Result.im := Sinh(z.re) * Sin(z.im);
end;

function csh(z: complex): complex;
begin
  Result.re := Sinh(z.re) * Cos(z.im);
  Result.im := Cosh(z.re) * Sin(z.im);
end;

function cth(z: complex): complex;
begin
  Result := csh(z) / cch(z);
end;

function carg_ch(z: complex): complex;
{ argch(z) = ln(z + i.sqrt(1 - z^2)) (FPC sign convention) }
begin
  Result := cneg(cln(z + i * csqrt(crsub(1.0, z * z))));
end;

function carg_sh(z: complex): complex;
{ argsh(z) = ln(z + sqrt(z^2 + 1)) }
begin
  Result := cln(z + csqrt(caddr(z * z, 1.0)));
end;

function carg_th(z: complex): complex;
{ argth(z) = ln((z + 1) / (1 - z)) / 2 }
begin
  Result := cdivr(cln(caddr(z, 1.0) / crsub(1.0, z)), 2.0);
end;

{ str(x:len:dec) with VARIABLE width/dec is a pxx frontend gap (the Str builtin
  only takes literal widths — ticket feature-pascal-str-variable-width), so the
  fixed-point formatting is done by hand here. }
function FmtFixed(v: Double; len, dec: Integer): string;
var
  scale: Double;
  total, ip, fp, sc: Int64;
  k: Integer;
  neg: Boolean;
  fs: string;
begin
  neg := v < 0.0;
  if neg then v := -v;
  if dec < 0 then dec := 0;
  scale := 1.0;
  for k := 1 to dec do scale := scale * 10.0;
  sc := Trunc(scale);
  total := Round(v * scale);
  ip := total div sc;
  fp := total mod sc;
  Str(ip, Result);
  if dec > 0 then
  begin
    Str(fp, fs);
    while Length(fs) < dec do fs := '0' + fs;
    Result := Result + '.' + fs;
  end;
  if neg then Result := '-' + Result;
  while Length(Result) < len do Result := ' ' + Result;
end;

function cstr(z: complex): string;
var istr, rstr: string;
begin
  Str(z.im, istr);
  Str(z.re, rstr);
  while (Length(istr) > 0) and (istr[1] = ' ') do
    Delete(istr, 1, 1);
  Result := rstr;
  if z.im < 0 then
    Result := Result + istr + 'i'
  else if z.im > 0 then
    Result := Result + '+' + istr + 'i';
end;

function cstr(z: complex; len: Integer): string;
var istr, rstr: string;
begin
  { FPC uses str(x:len) exponent format; pxx: default Str, left-padded }
  Str(z.im, istr);
  Str(z.re, rstr);
  while Length(rstr) < len do rstr := ' ' + rstr;
  while (Length(istr) > 0) and (istr[1] = ' ') do
    Delete(istr, 1, 1);
  Result := rstr;
  if z.im < 0 then
    Result := Result + istr + 'i'
  else if z.im > 0 then
    Result := Result + '+' + istr + 'i';
end;

function cstr(z: complex; len, dec: Integer): string;
var istr, rstr: string;
begin
  istr := FmtFixed(z.im, len, dec);
  rstr := FmtFixed(z.re, len, dec);
  while (Length(istr) > 0) and (istr[1] = ' ') do
    Delete(istr, 1, 1);
  Result := rstr;
  if z.im < 0 then
    Result := Result + istr + 'i'
  else if z.im > 0 then
    Result := Result + '+' + istr + 'i';
end;

end.
