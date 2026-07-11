program lib_ucomplex;

{ Golden test for lib/rtl/ucomplex.pas — and a deliberate workout for the
  operator-overloading frontend feature (chained operators, unit-scoped
  operator defs, FPC named-result declarations). Expected strings are exact:
  own-RTL math, FP-determinism rules. }

uses ucomplex;

procedure P(const tag: string; z: complex);
begin
  writeln(tag, '=', z.re:1:6, ' ', z.im:1:6);
end;

var
  a, b, z: complex;
  pi: Double;
begin
  a := cinit(3.0, 4.0);
  b := cinit(1.0, -2.0);

  { arithmetic identity: (3+4i)(1-2i)+(3+4i) = 14+2i — one chained expression }
  z := a * b + a;
  P('chain', z);

  { the four base ops }
  P('add', a + b);                      { 4-2i -> 4 -2 }
  P('sub', a - b);                      { 2+6i }
  P('mul', a * b);                      { 11-2i }
  P('div', a / b);                      { (3+4i)/(1-2i) = (-1+2i) }

  { equality + derived inequality }
  if a + b = cinit(4.0, 2.0) then writeln('eq=yes') else writeln('eq=no');
  if not (a = b) then writeln('neq=yes') else writeln('neq=no');

  { modulus / argument / conjugate / inverse }
  writeln('cmod=', cmod(a):1:6);        { 5.000000 }
  writeln('carg_i=', carg(i):1:6);      { pi/2 = 1.570796 }
  P('cong', cong(a));                   { 3-4i }
  P('cinv', cinv(cinit(0.0, 2.0)));     { 1/(2i) = -0.5i }

  { csqrt(-1) = i; csqrt(3+4i) = 2+i }
  P('csqrt-1', csqrt(cinit(-1.0, 0.0)));
  P('csqrt', csqrt(a));

  { cexp(i*pi) = -1; cln(e) = 1 }
  pi := 3.14159265358979323846;
  z := cexp(cinit(0.0, pi));
  writeln('cexp_ipi_re=', z.re:1:6);
  writeln('cexp_ipi_im_small=', Abs(z.im) < 1e-12);
  P('cln_e', cln(cinit(2.71828182845904523536, 0.0)));

  { square / power }
  P('csqr', csqr(a));                   { -7+24i }
  z := cpowr(cinit(0.0, 1.0), 2.0);     { i^2 = -1 }
  writeln('ipow2_re=', z.re:1:6);
  writeln('ipow2_im_small=', Abs(z.im) < 1e-12);

  { mixed complex/Double function forms }
  P('caddr', caddr(a, 1.0));            { 4+4i }
  P('csubr', csubr(a, 1.0));            { 2+4i }
  P('crsub', crsub(1.0, a));            { -2-4i }
  P('cmulr', cmulr(a, 2.0));            { 6+8i }
  P('cdivr', cdivr(a, 2.0));            { 1.5+2i }
  P('crdiv', crdiv(1.0, cinit(0.0, 1.0))); { 1/i = -i }
  P('cneg', cneg(a));                   { -3-4i }
  P('cdiv_fn', cdiv(a, b));             { same as a/b }

  { trig identity: sin^2 + cos^2 = 1 on a complex point }
  z := csqr(csin(b)) + csqr(ccos(b));
  writeln('sincos_re=', z.re:1:6);
  writeln('sincos_im_small=', Abs(z.im) < 1e-9);

  { csamevalue }
  writeln('same=', csamevalue(a / b * b, a));
  writeln('notsame=', csamevalue(a, b));

  { cstr forms }
  writeln('cstr=', cstr(cinit(1.0, -2.0), 1, 2));
  writeln('cstr0=', cstr(cinit(1.5, 0.0), 1, 2));
  writeln('cstrp=', cstr(cinit(-1.0, 2.0), 1, 2));
end.
