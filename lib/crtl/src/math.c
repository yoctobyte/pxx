/* SPDX-License-Identifier: Zlib */
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

/* trunc/round: Pascal's Trunc/Round are compiler INTRINSICS (lowered inline,
   no linkable symbol), so unlike sqrt/floor/ceil there is nothing for the
   case-insensitive extern bind to hit — a C call would survive to load time
   as `undefined symbol` (bug-c-math-round-undefined-symbol). Pure-C impls;
   note C round() is half-AWAY-FROM-ZERO, not Pascal Round's nearest-even.
   The (long long) cast truncates toward zero (verified against the C
   frontend's double->int64 lowering); |x| >= 2^63 is out of scope, like the
   other loop-form helpers here. */
double trunc(double x) {
  return (double)(long long)x;
}
double round(double x) {
  if (x >= 0.0) return (double)(long long)(x + 0.5);
  return (double)(long long)(x - 0.5);
}

/* frexp: x = m * 2^e with 0.5 <= |m| < 1. Loop form (no bit reinterpret — the C
   `*(unsigned long*)&double` punning path is unreliable here). */
double frexp(double x, int *e) {
  int n = 0;
  double a = x < 0.0 ? -x : x;
  if (x == 0.0) { *e = 0; return 0.0; }
  while (a >= 1.0) { a = a * 0.5; n++; }
  while (a <  0.5) { a = a * 2.0; n--; }
  *e = n;
  return x < 0.0 ? -a : a;
}

/* ldexp: x * 2^e by repeated doubling/halving (e bounded by the float range). */
double ldexp(double x, int e) {
  while (e > 0) { x = x * 2.0; e--; }
  while (e < 0) { x = x * 0.5; e++; }
  return x;
}

double modf(double x, double *ip) {
  double i;
  if (x < 0.0) i = -(double)((long)(-x)); else i = (double)((long)x);
  *ip = i;
  return x - i;
}
