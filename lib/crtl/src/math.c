/*
 * C runtime: math — bridges libm to the Pascal RTL math unit (lib/rtl/math.pas,
 * pulled by pxxcio's `uses math`). Project-owned, libc-free.
 *
 * KEY (case-insensitive name binding): the C frontend's FindProc is
 * case-insensitive across the C/Pascal namespace, so a C call to `sqrt`/`exp`/
 * `sin`/`floor`/`ceil`/`fmod`/`sinh`/`cosh`/`tanh`/`hypot`/`log2`/`log10` binds
 * DIRECTLY to the matching Pascal routine (Sqrt/Exp/Sin/...) with no wrapper —
 * lua's <math.h> extern is enough. So this file defines ONLY:
 *   - the name-mismatch cases, where the C name differs from the Pascal name and
 *     therefore does NOT collide with it: pow->Power, log->Ln, atan2->ArcTan2,
 *     asin->ArcSin, acos->ArcCos, atan->ArcTan;
 *   - fabs (calling Pascal Abs would collide with C int `abs`, so do it inline)
 *     and the pure IEEE ops frexp/ldexp/modf that have no Pascal equivalent.
 * A SAME-name wrapper (`double sqrt(double x){ return Sqrt(x); }`) must NOT be
 * written: `Sqrt` binds case-insensitively back to the C `sqrt` -> infinite
 * recursion. That is why the matching names are left to bind on their own.
 */

/* Pascal math.pas routines whose names differ from the C ones (no collision). */
extern double Ln(double x);
extern double Exp(double x);
extern double ArcTan2(double y, double x);
extern double ArcSin(double x);
extern double ArcCos(double x);
extern double ArcTan(double x);

/* pow goes through exp/ln rather than math.pas Power, because Power is OVERLOADED
   (Integer+Double) and a C extern binds to the Integer overload (returns garbage);
   Exp/Ln are single-signature and bind cleanly. b<=0 handled like C (0^0=1). */
double pow(double b, double e) {
  if (b == 0.0) return (e == 0.0) ? 1.0 : 0.0;
  if (b < 0.0)  return -Exp(e * Ln(-b));   /* lua only raises positive bases; sign best-effort */
  return Exp(e * Ln(b));
}
double log(double x)             { return Ln(x); }
double atan2(double y, double x) { return ArcTan2(y, x); }
double asin(double x)            { return ArcSin(x); }
double acos(double x)            { return ArcCos(x); }
double atan(double x)            { return ArcTan(x); }

double fabs(double x) { return x < 0.0 ? -x : x; }

/* frexp: x = m * 2^e, 0.5 <= |m| < 1. Decompose via the double's bit fields. */
double frexp(double x, int *e) {
  unsigned long bits = *(unsigned long *)&x;
  int exp = (int)((bits >> 52) & 0x7FF);
  double m;
  if (x == 0.0 || exp == 0x7FF) { *e = 0; return x; }   /* 0/inf/nan */
  if (exp == 0) {                                        /* subnormal: normalise */
    x = x * 18014398509481984.0;                         /* 2^54 */
    bits = *(unsigned long *)&x;
    exp = (int)((bits >> 52) & 0x7FF) - 54;
  }
  *e = exp - 1022;
  bits = (bits & 0x800FFFFFFFFFFFFFUL) | 0x3FE0000000000000UL;   /* exp -> [0.5,1) */
  m = *(double *)&bits;
  return m;
}

/* ldexp: x * 2^e. */
double ldexp(double x, int e) {
  while (e >  1000) { x = x * 8.98846567431158e307;   e -= 1023; }
  while (e < -1000) { x = x * 2.2250738585072014e-308; e += 1022; }
  {
    unsigned long bits = ((unsigned long)(e + 1023) & 0x7FF) << 52;
    double p = *(double *)&bits;
    return x * p;
  }
}

double modf(double x, double *ip) {
  double i;
  if (x < 0.0) { i = -(double)((long)(-x)); } else { i = (double)((long)x); }
  *ip = i;
  return x - i;
}
