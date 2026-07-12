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
double cbrt(double x) {
  /* Cube root, sign-preserving. Real cube root of a negative is negative,
     so route through |x| (pow's Exp*Ln path is positive-only). */
  if (x == 0.0) return 0.0;
  if (x < 0.0)  return -Exp(Ln(-x) / 3.0);
  return Exp(Ln(x) / 3.0);
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

/* long double == double in pxx: ldexpl forwards to ldexp. */
double ldexpl(double x, int e) { return ldexp(x, e); }

/* ---- float (single) variants — C99 <math.h> f-suffix family ------------- */
/* Graphics/game C (cglm etc.) calls these; pxx computes in double and narrows
   on return (correct within float precision — no separate single kernels).
   Relies on the cdecl float-return ABI fix (bug-c-float-single-return-zero). */
float fabsf(float x)  { return (float)fabs((double)x); }
float sqrtf(float x)  { return (float)sqrt((double)x); }
float sinf(float x)   { return (float)sin((double)x); }
float cosf(float x)   { return (float)cos((double)x); }
float tanf(float x)   { return (float)tan((double)x); }
float asinf(float x)  { return (float)asin((double)x); }
float acosf(float x)  { return (float)acos((double)x); }
float atanf(float x)  { return (float)atan((double)x); }
float atan2f(float y, float x) { return (float)atan2((double)y, (double)x); }
float floorf(float x) { return (float)floor((double)x); }
float ceilf(float x)  { return (float)ceil((double)x); }
float fmodf(float x, float y)  { return (float)fmod((double)x, (double)y); }
float powf(float b, float e)   { return (float)pow((double)b, (double)e); }
float expf(float x)   { return (float)exp((double)x); }
float logf(float x)   { return (float)log((double)x); }
float log2f(float x)  { return (float)(log((double)x) / 0.6931471805599453); }
float truncf(float x) { return (float)trunc((double)x); }
float roundf(float x) { return (float)round((double)x); }
float fminf(float a, float b) { return a < b ? a : b; }
float fmaxf(float a, float b) { return a > b ? a : b; }
double fmin(double a, double b) { return a < b ? a : b; }
double fmax(double a, double b) { return a > b ? a : b; }
float modff(float x, float *ip) {
  double di, r;
  r = modf((double)x, &di);
  *ip = (float)di;
  return (float)r;
}

/* ---- C99 additions for the QuickJS bring-up (feature-c-corpus-quickjs) --- */

/* scalbn == ldexp for binary floating point. */
double scalbn(double x, int e) { return ldexp(x, e); }

/* finite <=> x - x == 0 (inf - inf and nan - nan are NaN, NaN != 0). */
int isfinite(double x) { double d = x - x; return d == d && d == 0.0; }

/* IEEE bit-level sign/inf/next helpers. copysign/nextafter/isinf have NO
   Pascal RTL counterpart for the case-insensitive extern bind (unlike
   sin/floor/exp), so without C bodies here any caller silently picked up a
   libc DT_NEEDED — the same trap isnan had. Bit-punning through a pointer
   cast (verified against the C frontend); handles NaN and +/-0 exactly. */
double copysign(double x, double y) {
  unsigned long long xb = *(unsigned long long *)&x;
  unsigned long long yb = *(unsigned long long *)&y;
  xb = (xb & 0x7FFFFFFFFFFFFFFFull) | (yb & 0x8000000000000000ull);
  return *(double *)&xb;
}

int isinf(double x) {
  unsigned long long b = *(unsigned long long *)&x;
  return (b & 0x7FFFFFFFFFFFFFFFull) == 0x7FF0000000000000ull;
}

/* Next representable double after x toward y (C99). Magnitude-ordered bit
   walk: same-sign doubles order like their bit patterns; stepping the bits
   by 1 is exactly one ULP, crossing zero flips through +/-0. */
double nextafter(double x, double y) {
  unsigned long long xb, ax;
  if (x != x || y != y) return x + y;   /* NaN in -> NaN out */
  if (x == y) return y;
  xb = *(unsigned long long *)&x;
  ax = xb & 0x7FFFFFFFFFFFFFFFull;
  if (ax == 0) {                        /* +/-0: smallest subnormal toward y */
    xb = (y > 0.0) ? 1ull : 0x8000000000000001ull;
  } else if ((x < y) == !(xb >> 63)) {
    xb += 1;                            /* away from zero */
  } else {
    xb -= 1;                            /* toward zero */
  }
  return *(double *)&xb;
}

int signbit(double x) {
  return (int)(*(unsigned long long *)&x >> 63);
}

double nan(const char *tag) { (void)tag; return 0.0 / 0.0; }

/* NaN is the only value unequal to itself (float compares are IEEE-unordered
   since b232). Body here keeps callers libc-free — the bare extern otherwise
   resolves against libc and drags in a DT_NEEDED. */
int isnan(double x) { return x != x; }

/* IEEE remainder: r = x - n*y with n = nearest integer to x/y (ties to even).
   Built on fmod; the halfway case picks the even quotient like glibc. */
double remainder(double x, double y) {
  double ay = fabs(y);
  double r = fmod(x, y);
  double ar = fabs(r);
  if (2.0 * ar > ay ||
      (2.0 * ar == ay && fmod(trunc(fabs(x) / ay), 2.0) != 0.0))
    r -= copysign(ay, r);
  return r;
}

/* expm1/log1p: series for tiny arguments (where exp(x)-1 cancels), the plain
   formula elsewhere. Bring-up accuracy, not correctly-rounded. */
double expm1(double x) {
  if (fabs(x) < 1e-5)
    return x + 0.5 * x * x + (x * x * x) / 6.0;
  return exp(x) - 1.0;
}

double log1p(double x) {
  if (fabs(x) < 1e-5)
    return x - 0.5 * x * x + (x * x * x) / 3.0;
  return log(1.0 + x);
}

double acosh(double x) { return log(x + sqrt(x * x - 1.0)); }

double asinh(double x) {
  /* sign-symmetric; the log form loses the sign for negative x */
  return copysign(log(fabs(x) + sqrt(x * x + 1.0)), x);
}

double atanh(double x) { return 0.5 * log((1.0 + x) / (1.0 - x)); }
