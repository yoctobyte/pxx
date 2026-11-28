/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_MATH_H
#define PXX_CRTL_MATH_H 1

/* The M_* constants. Absent from this header until now, which was a SILENT
   wrong-value bug rather than a compile error: an undeclared identifier used as
   a value is treated as 0, so `M_PI` quietly became 0.0 and any geometry built
   on it came out plausible-looking and wrong. Found via vendored pdfgen, whose
   circle routine computes the Bezier offset (4/3)*(M_SQRT2-1)*r — with M_SQRT2
   at zero that is -1.333*r instead of +0.552*r, wrong in both sign and
   magnitude, so every circle it drew was garbage.

   Defined unconditionally, not behind _XOPEN_SOURCE/_USE_MATH_DEFINES the way
   glibc gates them. Real-world C reaches for M_PI constantly and often without
   setting any feature-test macro, and compiling real code as-is is the point;
   a program that DOES set the macro is unaffected either way.

   Values are the exact glibc spellings (20+ significant digits, deliberately
   past double precision so the nearest double is what gets stored). */
#define M_E        2.7182818284590452354   /* e */
#define M_LOG2E    1.4426950408889634074   /* log_2 e */
#define M_LOG10E   0.43429448190325182765  /* log_10 e */
#define M_LN2      0.69314718055994530942  /* log_e 2 */
#define M_LN10     2.30258509299404568402  /* log_e 10 */
#define M_PI       3.14159265358979323846  /* pi */
#define M_PI_2     1.57079632679489661923  /* pi/2 */
#define M_PI_4     0.78539816339744830962  /* pi/4 */
#define M_1_PI     0.31830988618379067154  /* 1/pi */
#define M_2_PI     0.63661977236758134308  /* 2/pi */
#define M_2_SQRTPI 1.12837916709551257390  /* 2/sqrt(pi) */
#define M_SQRT2    1.41421356237309504880  /* sqrt(2) */
#define M_SQRT1_2  0.70710678118654752440  /* 1/sqrt(2) */

/* Double-precision C math surface used by lua/sqlite. These resolve to libm/libc
   at link time via the external-symbol path; the declarations let the C frontend
   parse calls to them as functions rather than rejecting them as undeclared. */

extern double fabs(double x);
extern double floor(double x);
extern double ceil(double x);
extern double trunc(double x);
extern double round(double x);
extern double rint(double x);
extern double nearbyint(double x);
extern long lrint(double x);
extern long long llrint(double x);
/* lround/llround: round() then convert. NOT lrint — lrint follows the current
   rounding mode, lround is always half-away-from-zero, and splitting the pair
   was the odd part of the previous state (lrint existed, lround did not). */
extern long lround(double x);
extern long long llround(double x);
extern double sqrt(double x);
extern double cbrt(double x);
extern double sin(double x);
extern double cos(double x);
extern double tan(double x);
extern double asin(double x);
extern double acos(double x);
extern double atan(double x);
extern double atan2(double y, double x);
extern double sinh(double x);
extern double cosh(double x);
extern double tanh(double x);
/* exp / log2 / log10 / sin / cos / tan / sinh / cosh / tanh / hypot were
   defined under `__crtl_`-prefixed names and reached through function-like
   macros here, because the C name collided CASE-INSENSITIVELY with the Pascal
   RTL's Exp/Log2/Sin/... when the two were linked side by side: with two
   visible definitions the call bound to the wrong one and the arguments never
   arrived. That hazard is gone — `pxxcio.pas` no longer `uses math`, so the
   Pascal RTL is not in scope for an ordinary C program at all, and each of the
   ten now binds its own C body (measured per name, 2026-08-14 and again on the
   de-prefixing, 2026-08-16). They are ordinary C functions again.
   task-c-retire-the-crtl-name-dodge-prefixes */
extern double exp(double x);
extern double exp2(double x);
extern double log(double x);
extern double log2(double x);
extern double log10(double x);
extern double pow(double x, double y);
extern double fmod(double x, double y);
extern double frexp(double x, int *e);
extern double ldexp(double x, int e);
/* long double == double in pxx, so the `l` variants are thin aliases. */
extern double ldexpl(double x, int e);
/* The rest are function-like macros, not externs: under --system-libs
   (__PXX_SYSTEM_MATH__) an extern sqrtl would bind glibc's 80-bit long
   double sqrtl, whose ABI (x87 stack) is not pxx's 8-byte long double. Not
   static inline either: pxx emits an unused inline body, so every <math.h>
   user would reference round/llround/... that crtl does not define and be
   warned about a host-libc import (csystem_libs_granular_math_b112). A macro
   names the double function only where a program calls the l one.
   libxkbcommon's bench.c: llroundl(sqrtl(...)).
   feature-crtl-long-double-math-aliases */
#define sqrtl(x) sqrt(x)
#define fabsl(x) fabs(x)
#define floorl(x) floor(x)
#define ceill(x) ceil(x)
#define roundl(x) round(x)
#define lroundl(x) lround(x)
#define llroundl(x) llround(x)
#define truncl(x) trunc(x)
#define fmodl(x, y) fmod(x, y)
#define powl(x, y) pow(x, y)
#define expl(x) exp(x)
#define logl(x) log(x)
#define log2l(x) log2(x)
#define log10l(x) log10(x)
#define frexpl(x, e) frexp(x, e)
#define modfl(x, ip) modf(x, ip)
#define sinl(x) sin(x)
#define cosl(x) cos(x)
#define tanl(x) tan(x)
#define atanl(x) atan(x)
#define atan2l(y, x) atan2(y, x)
#define copysignl(x, y) copysign(x, y)
extern double modf(double x, double *iptr);
extern double hypot(double x, double y);
extern double copysign(double x, double y);
extern double nextafter(double x, double y);

extern int isnan(double x);
extern int isinf(double x);

/* float (single) variants (C99) + fmin/fmax — see src/math.c */
extern float fabsf(float x);
extern float sqrtf(float x);
extern float sinf(float x);
extern float cosf(float x);
extern float tanf(float x);
extern float asinf(float x);
extern float acosf(float x);
extern float atanf(float x);
extern float atan2f(float y, float x);
extern float floorf(float x);
extern float ceilf(float x);
extern float fmodf(float x, float y);
extern float powf(float b, float e);
extern float expf(float x);
extern float logf(float x);
extern float log2f(float x);
extern float truncf(float x);
extern float roundf(float x);
extern float fminf(float a, float b);
extern float fmaxf(float a, float b);
extern double fmin(double a, double b);
extern double fmax(double a, double b);

/* C99 additions the QuickJS bring-up needs (feature-c-corpus-quickjs).
 * isfinite/signbit are functions here, not type-generic macros — fine for
 * double-typed call sites, which is all the corpus uses. */
extern double scalbn(double x, int e);          /* == ldexp for binary FP */
extern int    isfinite(double x);
/* BSD finite() (isfinite's old name) and GNU sincos(): xedit's lisp and
   xclock use them. */
extern int    finite(double x);
extern int    finitef(float x);
extern void   sincos(double x, double *s, double *c);
extern void   sincosf(float x, float *s, float *c);
extern int    signbit(double x);
/* On the system-library path (an --emit-obj --system-libs object linked
   against the host libc) the bodies above are libc's, and glibc has no
   `isfinite` or `signbit` symbol -- both are macros there, over finite() and
   __signbit(), which it does export. Spelled the same way here, so such an
   object imports names that exist (wlroots' wlr_cursor.c). isnan and isinf
   glibc exports as they are. bug-c-system-libs-objects-import-crtl-only-names */
#ifdef __PXX_SYSTEM_MATH__
extern int __signbit(double x);
#define isfinite(x) finite(x)
#define signbit(x) __signbit(x)
#endif
extern double nan(const char *tag);
extern double remainder(double x, double y);    /* IEEE remainder */
extern double expm1(double x);
extern double log1p(double x);
extern double acosh(double x);
extern double asinh(double x);
extern double atanh(double x);
extern float modff(float x, float *ip);

/* HUGE_VAL: positive double overflow value used by lua for range checks. */
#define HUGE_VAL (1e308 * 10.0)
#define INFINITY (1e308 * 10.0)
/* A POSITIVE quiet NaN. `0.0 / 0.0` was the obvious spelling and it is the
   wrong one: on x86 that produces a NaN with the SIGN BIT SET, so printf
   rendered NAN as "-nan" where every other libc prints "nan" -- visible through
   %f, %e and %g, not just %a. The bit pattern is explicit so it does not depend
   on what the hardware happens to return for an invalid operation. */
static const union { unsigned long long __crtl_i; double __crtl_d; }
  __crtl_nan_bits = { 0x7ff8000000000000ULL };
#define NAN      (__crtl_nan_bits.__crtl_d)

#endif
