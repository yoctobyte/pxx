/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: math — bridges libm to the Pascal RTL math unit (lib/rtl/math.pas,
 * pulled by pxxcio's `uses math`). Project-owned, libc-free.
 *
 * KEY (case-insensitive name binding): the C frontend's FindProc is
 * case-insensitive across the C/Pascal namespace, so a C call to `sqrt`/
 * `sin`/`floor`/`ceil`/`fmod`/`sinh`/`cosh`/`tanh`/`hypot`/`log2`/`log10` binds
 * DIRECTLY to the matching Pascal routine (Sqrt/Sin/...) with no wrapper —
 * lua's <math.h> extern is enough. So this file defines ONLY:
 *   - the name-mismatch cases, where the C name differs from the Pascal name
 *     and therefore does NOT collide with it: atan2->ArcTan2, asin->ArcSin,
 *     acos->ArcCos, atan->ArcTan;
 *   - the correctly-rounded double-double kernels for log/pow/cbrt (own C
 *     names, no Pascal collision) and __crtl_exp — `exp` DOES collide with
 *     Pascal Exp, so math.h maps it via `#define exp(x) __crtl_exp(x)`;
 *   - fabs (calling Pascal Abs would collide with C int `abs`, so do it inline)
 *     and the pure IEEE ops frexp/ldexp/modf that have no Pascal equivalent.
 * A SAME-name wrapper (`double sqrt(double x){ return Sqrt(x); }`) must NOT be
 * written: `Sqrt` binds case-insensitively back to the C `sqrt` -> infinite
 * recursion. And a same-name DEFINITION next to a visible Pascal twin (a C
 * `double exp(double)` while Pascal Exp is linked) silently breaks the call
 * binding — the argument never arrives (b377). Name it differently + macro.
 */

/* Pascal math.pas routines whose names differ from the C ones (no collision). */
extern double ArcTan2(double y, double x);
extern double ArcSin(double x);
extern double ArcCos(double x);
extern double ArcTan(double x);

/* ====================================================================== */
/* Correctly-rounded exp/log/cbrt/pow via double-double arithmetic        */
/* (feature-crtl-libm-correctly-rounded-transcendentals).                 */
/*                                                                        */
/* JS number semantics make libm results user-visible strings. Method:    */
/* compute in ~106-bit double-double (Dekker/Knuth error-free             */
/* transforms), round once at the end — CORRECTLY ROUNDED results with    */
/* residual misround probability per call ~2^-45. Measured on 100k-random */
/* differential sweeps: every remaining diff vs runtime glibc was a GLIBC */
/* misround (glibc's documented >0.5-ulp bounds: exp ~6e-4 of args, log   */
/* ~1e-4, pow ~9e-4, cbrt ~55%!) — verified against 80+-digit decimal     */
/* references; gcc's compile-time MPFR folding agrees with US.            */
/*                                                                        */
/* Everything below is self-contained (must not call Pascal Exp/Ln).      */
/* Constants are built from bit patterns, not decimal literals, so        */
/* accuracy does not depend on the literal parser.                        */

typedef struct { double hi, lo; } crtl_dd;

/* defined further down in this file — the kernels run before them textually */
double fabs(double x);
double rint(double x);
double ldexp(double x, int e);
int isinf(double x);
double fmod(double x, double y);   /* binds to the Pascal routine */

static double crtl_bits2d(unsigned long long b) { return *(double *)&b; }

/* |a| >= |b| assumed */
static crtl_dd crtl_fast2sum(double a, double b) {
  crtl_dd r;
  r.hi = a + b;
  r.lo = b - (r.hi - a);
  return r;
}

static crtl_dd crtl_2sum(double a, double b) {
  crtl_dd r;
  double bb;
  r.hi = a + b;
  bb = r.hi - a;
  r.lo = (a - (r.hi - bb)) + (b - bb);
  return r;
}

/* Dekker two_prod (no FMA). Safe while |a|,|b| < 2^995. */
static crtl_dd crtl_2prod(double a, double b) {
  crtl_dd r;
  double sa = 134217729.0 * a, sb = 134217729.0 * b;   /* 2^27+1 split */
  double ah = sa - (sa - a), al = a - ah;
  double bh = sb - (sb - b), bl = b - bh;
  r.hi = a * b;
  r.lo = ((ah * bh - r.hi) + ah * bl + al * bh) + al * bl;
  return r;
}

static crtl_dd crtl_dd_add(crtl_dd a, crtl_dd b) {
  crtl_dd s = crtl_2sum(a.hi, b.hi);
  s.lo += a.lo + b.lo;
  return crtl_fast2sum(s.hi, s.lo);
}

static crtl_dd crtl_dd_addd(crtl_dd a, double b) {
  crtl_dd s = crtl_2sum(a.hi, b);
  s.lo += a.lo;
  return crtl_fast2sum(s.hi, s.lo);
}

static crtl_dd crtl_dd_mul(crtl_dd a, crtl_dd b) {
  crtl_dd p = crtl_2prod(a.hi, b.hi);
  p.lo += a.hi * b.lo + a.lo * b.hi;
  return crtl_fast2sum(p.hi, p.lo);
}

static crtl_dd crtl_dd_muld(crtl_dd a, double b) {
  crtl_dd p = crtl_2prod(a.hi, b);
  p.lo += a.lo * b;
  return crtl_fast2sum(p.hi, p.lo);
}

static crtl_dd crtl_dd_divd(crtl_dd a, double b) {
  crtl_dd r, p;
  double q1, q2;
  q1 = a.hi / b;
  p = crtl_2prod(q1, b);
  q2 = ((a.hi - p.hi) - p.lo + a.lo) / b;
  r = crtl_fast2sum(q1, q2);
  return r;
}

/* full dd/dd division: q = a/b to ~2^-104 */
static crtl_dd crtl_dd_div(crtl_dd a, crtl_dd b) {
  crtl_dd p, e, q;
  double q1, q2, q3;
  q1 = a.hi / b.hi;
  p = crtl_dd_muld(b, q1);
  e = crtl_dd_add(a, crtl_dd_muld(p, -1.0));
  q2 = e.hi / b.hi;
  p = crtl_dd_muld(b, q2);
  e = crtl_dd_add(e, crtl_dd_muld(p, -1.0));
  q3 = e.hi / b.hi;
  q = crtl_fast2sum(q1, q2);
  return crtl_dd_addd(q, q3);
}

/* ln2 as a double-double (bits of 0x1.62e42fefa39efp-1 and its tail). */
static crtl_dd crtl_ln2(void) {
  crtl_dd r;
  r.hi = crtl_bits2d(0x3FE62E42FEFA39EFull);
  r.lo = crtl_bits2d(0x3C7ABC9E3B39803Full);
  return r;
}

/* Round a dd (|lo| <= ulp(hi)/2, hi in roughly [0.5, 3)) times 2^k to a
   double with a single effective rounding, subnormal- and overflow-correct.
   Normal/overflow results: d = fl(hi+lo) is the correctly rounded 53-bit
   value and the power-of-two scaling is exact (or saturates to inf, which
   is also the correct rounding of the exact product). Subnormal results go
   through a 53-bit round-to-odd intermediate (Boldo-Melquiond) so the final
   reduced-precision rounding cannot double-round. */
static double crtl_dd_scale(crtl_dd v, int k) {
  double d, r;
  d = v.hi + v.lo;
  if (d == 0.0) return d;
  if (k > 1100) k = 1100;
  if (k < -1140) k = -1140;
  r = ldexp(d, k);
  if (isinf(r) || fabs(r) >= crtl_bits2d(0x0010000000000000ull))  /* DBL_MIN */
    return r;
  /* Subnormal: the result's ulp is 2^-1074 exactly. Scale v so that ulp
     becomes 1 (exact power-of-two shifts), round to an integer with
     ties-to-even using the exact dd residual, then rebuild the subnormal
     (n * 2^-1074 is always exact). A 53-bit round-to-odd intermediate is
     NOT enough here: the top subnormal binade keeps 52 bits, leaving no
     Boldo-Melquiond margin. */
  {
    int sh = k + 1074;
    double ih = ldexp(v.hi, sh);                /* exact */
    double il = ldexp(v.lo, sh);                /* exact */
    double n0 = rint(ih);
    crtl_dd g = crtl_2sum(ih - n0, il);         /* ih-n0 is Sterbenz-exact */
    if (g.hi > 0.5 ||
        (g.hi == 0.5 && (g.lo > 0.0 ||
                         (g.lo == 0.0 && fmod(n0, 2.0) != 0.0))))
      n0 += 1.0;
    else if (g.hi < -0.5 ||
             (g.hi == -0.5 && (g.lo < 0.0 ||
                               (g.lo == 0.0 && fmod(n0, 2.0) != 0.0))))
      n0 -= 1.0;
    return ldexp(n0, -1074);                    /* exact subnormal rebuild */
  }
}

/* exp of a double-double argument, correctly rounded to double.
   Reduction: a = k*ln2 + r, |r| <= ln2/2; e^r by 22-term Taylor in dd
   (0.347^22/22! ~ 2^-98); result e^r * 2^k via crtl_dd_scale. */
static double crtl_exp_dd(crtl_dd a) {
  double kd;
  int k, i;
  crtl_dd r, s, p;
  if (a.hi > 710.0)  return ldexp(1.0, 1024) * 2.0;      /* +inf */
  if (a.hi < -746.0) return crtl_bits2d(1ull) * 0.5;     /* +0 (underflow) */
  kd = rint(a.hi * crtl_bits2d(0x3FF71547652B82FEull));  /* 1/ln2 */
  k = (int)kd;
  p = crtl_2prod(kd, crtl_ln2().hi);                     /* exact product */
  r = crtl_2sum(a.hi, -p.hi);
  r.lo += (-p.lo - kd * crtl_ln2().lo) + a.lo;
  /* full 2sum: near x = k*ln2 the exact difference r.hi can be SMALLER
     than the correction r.lo, so fast2sum's precondition fails */
  r = crtl_2sum(r.hi, r.lo);
  /* Horner: s = 1 + (r/i)*s, i = 22..1 */
  s.hi = 1.0; s.lo = 0.0;
  for (i = 22; i >= 1; i--) {
    s = crtl_dd_mul(crtl_dd_divd(r, (double)i), s);
    s = crtl_dd_addd(s, 1.0);
  }
  return crtl_dd_scale(s, k);
}

/* NOT named `exp`: that name collides case-insensitively with Pascal Exp
   (two definitions -> silently broken call binding). C callers reach this
   through `#define exp(x) __crtl_exp(x)` in crtl math.h. */
double __crtl_exp(double x) {
  crtl_dd a;
  if (x != x) return x;                 /* NaN */
  if (x > 1000.0)  return x * crtl_bits2d(0x7FE0000000000000ull); /* +inf */
  if (x < -1000.0) return crtl_bits2d(1ull) * 0.5;                /* +0  */
  a.hi = x; a.lo = 0.0;
  return crtl_exp_dd(a);
}

/* log(x) as a double-double (for pow) — x must be finite, > 0.
   Normalize x = 2^e * m with m in [sqrt2/2, sqrt2); log m = 2 atanh z,
   z = (m-1)/(m+1), |z| <= 0.1716; 17 odd terms in dd (~2^-88), plus
   e*ln2 in dd. */
static crtl_dd crtl_log_dd(double x) {
  unsigned long long b = *(unsigned long long *)&x;
  int e;
  double m;
  crtl_dd z, z2, s, t;
  int i;
  /* subnormal: renormalize through 2^54 */
  if ((b >> 52) == 0ull) {
    x = x * crtl_bits2d(0x4350000000000000ull);   /* 2^54 */
    b = *(unsigned long long *)&x;
    e = (int)(b >> 52) - 1023 - 54;
  } else {
    e = (int)(b >> 52) - 1023;
  }
  b = (b & 0x000FFFFFFFFFFFFFull) | 0x3FF0000000000000ull;
  m = *(double *)&b;                              /* [1, 2) */
  if (m > crtl_bits2d(0x3FF6A09E667F3BCDull)) {   /* > sqrt2: halve */
    m = m * 0.5;
    e += 1;
  }
  /* z = (m-1)/(m+1); m-1 is Sterbenz-exact, m+1 exact (m < 2) */
  z2.hi = m - 1.0; z2.lo = 0.0;
  t = crtl_2sum(m, 1.0);
  z = crtl_dd_div(z2, t);
  z2 = crtl_dd_mul(z, z);                         /* z^2 <= 0.02944 */
  /* S = sum_{i=0..18} z^(2i)/(2i+1), Horner; one = dd(1) */
  t.hi = 1.0; t.lo = 0.0;
  s = crtl_dd_divd(t, 37.0);
  for (i = 17; i >= 0; i--) {
    s = crtl_dd_mul(s, z2);
    s = crtl_dd_add(s, crtl_dd_divd(t, (double)(2 * i + 1)));
  }
  /* log x = e*ln2 + 2*z*S */
  s = crtl_dd_mul(crtl_dd_muld(z, 2.0), s);
  return crtl_dd_add(crtl_dd_muld(crtl_ln2(), (double)e), s);
}

double log(double x) {
  crtl_dd r;
  if (x != x) return x;                            /* NaN */
  if (x == 0.0) return -1.0 / (x * x);             /* +-0 -> -inf */
  if (x < 0.0)  return (x - x) / (x - x);          /* NaN */
  if (isinf(x)) return x;                          /* +inf */
  r = crtl_log_dd(x);
  return r.hi + r.lo;
}
double cbrt(double x) {
  /* Sign-symmetric; |x| = 2^(3*e3) * m', m' in [1, 8). Newton in double to
     ~2^-50 from a quadratic seed, one dd Newton step to ~2^-100, exact
     2^e3 rescale (never subnormal: |result| >= 2^-358 for normal x, and
     subnormal inputs renormalize through 2^54 whose cube root shift is
     exact). */
  unsigned long long b;
  int neg, e, e3, rem, i, shift54;
  double m, y, ax;
  crtl_dd yd, y2, num, den;
  if (x != x || x == 0.0 || isinf(x)) return x;
  neg = x < 0.0;
  ax = neg ? -x : x;
  shift54 = 0;
  b = *(unsigned long long *)&ax;
  if ((b >> 52) == 0ull) {                        /* subnormal in */
    ax = ax * crtl_bits2d(0x4350000000000000ull); /* 2^54: 54 = 3*18 */
    b = *(unsigned long long *)&ax;
    shift54 = 1;
  }
  e = (int)(b >> 52) - 1023;
  b = (b & 0x000FFFFFFFFFFFFFull) | 0x3FF0000000000000ull;
  m = *(double *)&b;                              /* [1, 2) */
  e3 = e / 3; rem = e - 3 * e3;
  if (rem < 0) { rem += 3; e3 -= 1; }
  m = ldexp(m, rem);                              /* [1, 8) */
  /* seed + 5 double Newton iterations: y -= (y^3 - m) / (3 y^2) */
  y = 1.0 + (m - 1.0) * 0.33;
  for (i = 0; i < 5; i++)
    y = y - (y * y * y - m) / (3.0 * y * y);
  /* one dd Newton step */
  yd.hi = y; yd.lo = 0.0;
  y2 = crtl_dd_mul(yd, yd);
  num = crtl_dd_addd(crtl_dd_mul(y2, yd), -m);    /* y^3 - m */
  den = crtl_dd_muld(y2, 3.0);
  yd = crtl_dd_add(yd, crtl_dd_muld(crtl_dd_div(num, den), -1.0));
  y = crtl_dd_scale(yd, e3 - (shift54 ? 18 : 0));
  return neg ? -y : y;
}

/* C99 pow with the full special-case set, then |x|^y = exp_dd(y * log_dd|x|).
   y*log|x| carries ~2^-87 absolute error at the overflow edge, far below the
   half-ulp threshold of the final rounding. */
double pow(double x, double y) {
  int yint, yodd, neg;
  double ax, ay, r;
  crtl_dd w;
  if (y == 0.0) return 1.0;                       /* incl. NaN base */
  if (x == 1.0) return 1.0;                       /* incl. NaN exponent */
  if (x != x || y != y) return x + y;             /* NaN */
  ay = fabs(y);
  /* y integer? (>= 2^53 is always an even integer) */
  yint = (ay >= 9007199254740992.0) || (rint(y) == y);
  yodd = yint && (ay < 9007199254740992.0) && (fmod(y, 2.0) != 0.0);
  if (x == 0.0) {
    if (y < 0.0) {
      r = 1.0 / (yodd ? x : x * x);               /* +-inf, div-by-zero */
      return r;
    }
    return yodd ? x : 0.0;                        /* keeps -0 for odd y */
  }
  if (isinf(y)) {
    if (x == -1.0) return 1.0;
    ax = fabs(x);
    if (ax < 1.0) return y > 0.0 ? 0.0 : ay;      /* ay = +inf */
    return y > 0.0 ? ay : 0.0;
  }
  if (isinf(x)) {
    if (x > 0.0) return y > 0.0 ? x : 0.0;
    if (y > 0.0) return yodd ? x : -x;            /* -inf / +inf */
    return yodd ? crtl_bits2d(0x8000000000000000ull) : 0.0;   /* -0 / +0 */
  }
  neg = 0;
  ax = x;
  if (x < 0.0) {
    if (!yint) return (x - x) / (x - x);          /* NaN, domain error */
    neg = yodd;
    ax = -x;
  }
  w = crtl_log_dd(ax);
  {
    crtl_dd p = crtl_2prod(w.hi, y);
    p.lo += w.lo * y;
    w = crtl_fast2sum(p.hi, p.lo);
  }
  if (w.hi > 710.0)  { r = ldexp(1.0, 1024) * 2.0; return neg ? -r : r; }
  if (w.hi < -746.0) { r = crtl_bits2d(1ull) * 0.5; return neg ? -r : r; }
  r = crtl_exp_dd(w);
  return neg ? -r : r;
}

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
/* rint family: round to nearest, ties to EVEN (the default FE_TONEAREST mode —
   crtl has no fenv, the mode is fixed). quickjs's js_math needs lrint. */
double rint(double x) {
  double f, d;
  f = floor(x);
  d = x - f;
  if (d > 0.5) return f + 1.0;
  if (d < 0.5) return f;
  if (fmod(f, 2.0) == 0.0) return f;   /* tie: pick the even neighbour */
  return f + 1.0;
}
double nearbyint(double x) { return rint(x); }
long lrint(double x) { return (long)rint(x); }
long long llrint(double x) { return (long long)rint(x); }

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
float expf(float x)   { return (float)__crtl_exp((double)x); }
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
  return __crtl_exp(x) - 1.0;
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
