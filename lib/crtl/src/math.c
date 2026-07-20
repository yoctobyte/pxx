/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: math — bridges libm to the Pascal RTL math unit (lib/rtl/math.pas,
 * pulled by pxxcio's `uses math`). Project-owned, libc-free.
 *
 * KEY (case-insensitive name binding): the C frontend's FindProc is
 * case-insensitive across the C/Pascal namespace, so a C call to `sqrt`/
 * `sin`/`floor`/`ceil`/`fmod`/`sinh`/`cosh`/`tanh`/`hypot` binds
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
double floor(double x);
int isinf(double x);
double fmod(double x, double y);   /* binds to the Pascal routine */
double sqrt(double x);             /* binds to the Pascal routine */

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

/* Shared exp reduction: a = k*ln2 + r, |r| <= ln2/2; returns e^r as a dd
   (in [0.7, 1.42]) by 22-term Taylor (0.347^22/22! ~ 2^-98) and k via *kp.
   Caller must have bounded a.hi to the finite-result range. */
static crtl_dd crtl_exp_core(crtl_dd a, int *kp) {
  double kd;
  int i;
  crtl_dd r, s, p;
  kd = rint(a.hi * crtl_bits2d(0x3FF71547652B82FEull));  /* 1/ln2 */
  *kp = (int)kd;
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
  return s;
}

/* exp of a double-double argument, correctly rounded to double. */
static double crtl_exp_dd(crtl_dd a) {
  int k;
  crtl_dd s;
  if (a.hi > 710.0)  return ldexp(1.0, 1024) * 2.0;      /* +inf */
  if (a.hi < -746.0) return crtl_bits2d(1ull) * 0.5;     /* +0 (underflow) */
  s = crtl_exp_core(a, &k);
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
static crtl_dd crtl_log_ddx(crtl_dd w) {
  unsigned long long b;
  int e;
  double x = w.hi, m;
  crtl_dd md, z, z2, s, t, num, den;
  int i;
  b = *(unsigned long long *)&x;
  /* subnormal: renormalize through 2^54 (a dd input is never subnormal) */
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
  md.hi = m;
  md.lo = ldexp(w.lo, -e);                        /* exact power-of-two shift */
  /* z = (m-1)/(m+1); m-1 is Sterbenz-exact in the hi part, m+1 exact (m < 2) */
  num = crtl_dd_addd(md, -1.0);
  den = crtl_dd_addd(md, 1.0);
  z = crtl_dd_div(num, den);
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

static crtl_dd crtl_log_dd(double x) {
  crtl_dd w;
  w.hi = x; w.lo = 0.0;
  return crtl_log_ddx(w);
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

/* log2/log10: log_dd(x) times the dd constant 1/ln2 resp. 1/ln10 — keeps
   the exact cases (log2(2^n) = n, log10(10^n) = n) and correct rounding.
   NOT named log2/log10: those collide case-insensitively with Pascal
   Log2/Log10 (same silently-broken binding as exp/Exp, b377) — C callers
   come through the math.h function-like macros. */
double __crtl_log2(double x) {
  crtl_dd r, c;
  if (x != x) return x;
  if (x == 0.0) return -1.0 / (x * x);
  if (x < 0.0)  return (x - x) / (x - x);
  if (isinf(x)) return x;
  c.hi = crtl_bits2d(0x3FF71547652B82FEull);       /* 1/ln2 */
  c.lo = crtl_bits2d(0x3C7777D0FFDA0D24ull);
  r = crtl_dd_mul(crtl_log_dd(x), c);
  return r.hi + r.lo;
}

double __crtl_log10(double x) {
  crtl_dd r, c;
  if (x != x) return x;
  if (x == 0.0) return -1.0 / (x * x);
  if (x < 0.0)  return (x - x) / (x - x);
  if (isinf(x)) return x;
  c.hi = crtl_bits2d(0x3FDBCB7B1526E50Eull);       /* 1/ln10 */
  c.lo = crtl_bits2d(0x3C695355BAAAFAD3ull);
  r = crtl_dd_mul(crtl_log_dd(x), c);
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

/* ---- correctly-rounded trigonometry on the dd kernels ------------------- */

/* Argument reduction x = n*(pi/2) + r, |r| <= pi/4(1+eps), r as a dd.
   Cody-Waite with pi/2 split into three 24-bit chunks (n*chunk exact for
   |n| < 2^28) plus a dd tail — r carries ~2^-150 absolute error, enough
   for full relative accuracy down to the closest double to a multiple of
   pi/2 (~2^-54 away). VALID FOR |x| < 1e8 ONLY; the caller falls back to
   the Pascal routines beyond that (huge-argument Payne-Hanek reduction is
   a known gap, noted in the ticket). Returns the quadrant (n mod 4). */
static int crtl_trig_reduce(double x, crtl_dd *r) {
  double nd, s1, s2;
  long long n;
  crtl_dd t, p;
  nd = rint(x * crtl_bits2d(0x3FE45F306DC9C883ull));    /* x * 2/pi */
  n = (long long)nd;
  if (n == 0) { r->hi = x; r->lo = 0.0; return 0; }
  s1 = x  - nd * crtl_bits2d(0x3FF921FB60000000ull);    /* pi/2 chunk A, exact */
  s2 = s1 - nd * crtl_bits2d(0xBE6777A5C0000000ull);    /* chunk B, exact */
  t  = crtl_2sum(s2, -(nd * crtl_bits2d(0xBCDEE59DA0000000ull)));  /* chunk C */
  p  = crtl_2prod(nd, crtl_bits2d(0x3B298A2E03707345ull));         /* dd tail d1 */
  t  = crtl_dd_add(t, crtl_dd_neg(p));
  t.lo -= nd * crtl_bits2d(0xB7C6FDB1F7759834ull);                 /* d2 (tiny) */
  *r = crtl_2sum(t.hi, t.lo);
  return (int)(n & 3);
}

/* ---- Payne-Hanek reduction, for |x| >= 1e8 -------------------------------
   Cody-Waite above runs out at 1e8: it subtracts a few fixed chunks of pi/2, so
   once x is large enough that x*2/pi needs more bits than those chunks carry,
   the result is dominated by the bits that were never there. Payne-Hanek fixes
   that by multiplying by a 2/pi expansion long enough for ANY double.

   2/pi as 24-bit chunks, 1440 bits. 24 is not arbitrary: a 24x24-bit product is
   below 2^48 and therefore EXACT in a double, which is what lets the whole
   convolution run in plain double arithmetic with no int128 and no error term.
   Derived at 700 decimal digits; the leading entries match fdlibm's published
   ipio2 (0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, ...), which is the check that
   the derivation is right and not merely self-consistent. */
static const double crtl_ipio2[60] = {
    10680707.0,    7228996.0,    1387004.0,    2578385.0,
    16069853.0,   12639074.0,    9804092.0,    4427841.0,
    16666979.0,   11263675.0,   12935607.0,    2387514.0,
     4345298.0,   14681673.0,    3074569.0,   13734428.0,
    16653803.0,    1880361.0,   10960616.0,    8533493.0,
     3062596.0,    8710556.0,    7349940.0,    6258241.0,
     3772886.0,    3769171.0,    3798172.0,    8675211.0,
    12450088.0,    3874808.0,    9961438.0,     366607.0,
    15675153.0,    9132554.0,    7151469.0,    3571407.0,
     2607881.0,   12013382.0,    4155038.0,    6285869.0,
     7677882.0,   13102053.0,   15825725.0,     473591.0,
     9065106.0,   15363067.0,    6271263.0,    9264392.0,
     5636912.0,    4652155.0,    7056368.0,   13614112.0,
    10155062.0,    1944035.0,    9527646.0,   15080200.0,
     6658437.0,    6231200.0,    6832269.0,   16767104.0
};

static crtl_dd crtl_pio2(void);

/* Reduce ax = |x| (finite, >= 1e8). Returns q in 0..3 (the quadrant) and sets
   *r to the reduced argument with |*r| <= pi/4.

   Writing ax = X * 2^(e0-48) with X three 24-bit chunks, and 2/pi as the chunk
   sum above, the product collects by k = i+j into terms C_k * 2^(e0-24(k+1)).
   Only the low two integer bits survive `mod 4`, so terms whose exponent is >= 2
   contribute a multiple of 4 and are skipped outright — that is what keeps the
   work constant regardless of how enormous x is. */
static int crtl_trig_reduce_big(double ax, crtl_dd *r) {
  double tx[3], z, ck, t, nd;
  crtl_dd acc, fr;
  int e0, k, kstart, i, j, ek, q;

  e0 = 0;
  z = ax;
  /* e0 such that ax * 2^-e0 lands in [2^23, 2^24) */
  while (z >= 16777216.0) { z *= 0.5; e0++; }
  while (z < 8388608.0)   { z *= 2.0; e0--; }

  for (i = 0; i < 3; i++) {
    tx[i] = (double)(long long)z;          /* z >= 0, integral part */
    z = (z - tx[i]) * 16777216.0;
  }

  /* first k whose term can still matter mod 4 */
  kstart = 0;
  while (e0 - 24 * (kstart + 1) > 1) kstart++;

  acc.hi = 0.0; acc.lo = 0.0;
  for (k = kstart; k <= kstart + 7; k++) {
    ek = e0 - 24 * (k + 1);
    ck = 0.0;
    for (j = 0; j < 3; j++) {
      i = k - j;
      if (i < 0 || i >= 60) continue;
      /* exact: each product < 2^48, at most three of them, sum < 2^50 */
      ck += tx[j] * crtl_ipio2[i];
    }
    if (ck == 0.0) continue;
    t = ldexp(ck, ek);
    /* Reduce mod 4 while t is still exactly representable. t carries 50
       significant bits; the residue needs at most 2 integer bits plus t's
       fractional bits, and whenever t >= 4 that total stays inside 53 — so this
       subtraction is exact, not merely close. */
    if (t >= 4.0 || t <= -4.0) t = t - 4.0 * floor(t * 0.25);
    acc = crtl_dd_add(acc, crtl_2sum(t, 0.0));
  }

  /* fold the accumulated terms back into [0,4), then split into quadrant and
     a residue in [-1/2, 1/2] so |r| <= pi/4 for the kernels */
  t = floor((acc.hi + acc.lo) * 0.25);
  acc = crtl_dd_add(acc, crtl_2sum(-4.0 * t, 0.0));
  nd = rint(acc.hi + acc.lo);
  fr = crtl_dd_add(acc, crtl_2sum(-nd, 0.0));
  q = (int)nd & 3;
  *r = crtl_dd_mul(fr, crtl_pio2());
  return q;
}

/* sin/cos of a reduced dd argument, |r| <= ~0.786, by 13-term dd Taylor. */
static crtl_dd crtl_sin_kernel(crtl_dd r) {
  crtl_dd r2, s;
  int k;
  r2 = crtl_dd_mul(r, r);
  s.hi = 1.0; s.lo = 0.0;
  for (k = 13; k >= 1; k--) {
    s = crtl_dd_mul(crtl_dd_divd(r2, (double)(2 * k * (2 * k + 1))), s);
    s = crtl_dd_add(crtl_2sum(1.0, 0.0), crtl_dd_neg(s));   /* 1 - term*s */
  }
  return crtl_dd_mul(r, s);
}

static crtl_dd crtl_cos_kernel(crtl_dd r) {
  crtl_dd r2, s;
  int k;
  r2 = crtl_dd_mul(r, r);
  s.hi = 1.0; s.lo = 0.0;
  for (k = 13; k >= 1; k--) {
    s = crtl_dd_mul(crtl_dd_divd(r2, (double)((2 * k - 1) * 2 * k)), s);
    s = crtl_dd_add(crtl_2sum(1.0, 0.0), crtl_dd_neg(s));
  }
  return s;
}

/* sin and cos of x via the quadrant identity; valid for |x| < 1e8. */
static void crtl_sincos_dd(double x, crtl_dd *sn, crtl_dd *cs) {
  crtl_dd r, a, b;
  int q = crtl_trig_reduce(x, &r);
  a = crtl_sin_kernel(r);
  b = crtl_cos_kernel(r);
  switch (q) {
    case 0: *sn = a; *cs = b; break;
    case 1: *sn = b; *cs = crtl_dd_neg(a); break;
    case 2: *sn = crtl_dd_neg(a); *cs = crtl_dd_neg(b); break;
    default: *sn = crtl_dd_neg(b); *cs = a; break;
  }
}

/* sin/cos of a huge argument, via Payne-Hanek. Mirrors crtl_sincos_dd's
   quadrant mapping; ax must be |x|, so the caller reapplies the sign (sin and
   tan are odd, cos is even). */
static void crtl_sincos_big(double ax, crtl_dd *sn, crtl_dd *cs) {
  crtl_dd r, a, b;
  int q = crtl_trig_reduce_big(ax, &r);
  a = crtl_sin_kernel(r);
  b = crtl_cos_kernel(r);
  switch (q) {
    case 0: *sn = a; *cs = b; break;
    case 1: *sn = b; *cs = crtl_dd_neg(a); break;
    case 2: *sn = crtl_dd_neg(a); *cs = crtl_dd_neg(b); break;
    default: *sn = crtl_dd_neg(b); *cs = a; break;
  }
}

/* NOT named sin/cos/tan: Pascal Sin/Cos/Tan collide (b377 landmine) —
   C callers come through the math.h function-like macros. */
double __crtl_sin(double x) {
  crtl_dd sn, cs;
  if (x != x || x == 0.0) return x;
  if (isinf(x)) return (x - x) / (x - x);
  if (fabs(x) >= 1.0e8) {
    crtl_sincos_big(fabs(x), &sn, &cs);
    return x < 0.0 ? -(sn.hi + sn.lo) : (sn.hi + sn.lo);
  }
  crtl_sincos_dd(x, &sn, &cs);
  return sn.hi + sn.lo;
}

double __crtl_cos(double x) {
  crtl_dd sn, cs;
  if (x != x) return x;
  if (isinf(x)) return (x - x) / (x - x);
  if (fabs(x) >= 1.0e8) {
    crtl_sincos_big(fabs(x), &sn, &cs);   /* cos is even: no sign fixup */
    return cs.hi + cs.lo;
  }
  crtl_sincos_dd(x, &sn, &cs);
  return cs.hi + cs.lo;
}

double __crtl_tan(double x) {
  crtl_dd sn, cs, t;
  if (x != x || x == 0.0) return x;
  if (isinf(x)) return (x - x) / (x - x);
  if (fabs(x) >= 1.0e8) {
    crtl_sincos_big(fabs(x), &sn, &cs);
    t = crtl_dd_div(sn, cs);
    return x < 0.0 ? -(t.hi + t.lo) : (t.hi + t.lo);
  }
  crtl_sincos_dd(x, &sn, &cs);
  t = crtl_dd_div(sn, cs);
  return t.hi + t.lo;
}

/* pi/2 and pi as dds for the inverse functions. */
static crtl_dd crtl_pio2(void) {
  crtl_dd r;
  r.hi = crtl_bits2d(0x3FF921FB54442D18ull);
  r.lo = crtl_bits2d(0x3C91A62633145C07ull);
  return r;
}
static crtl_dd crtl_pi(void) {
  crtl_dd r;
  r.hi = crtl_bits2d(0x400921FB54442D18ull);
  r.lo = crtl_bits2d(0x3CA1A62633145C07ull);
  return r;
}

/* atan of a non-negative dd argument. t > 1 inverts around pi/2; then
   half-angle t <- t/(1+sqrt(1+t^2)) until t < 0.0625 (doubling count h),
   then a 13-term alternating odd series, result scaled by 2^h. */
static crtl_dd crtl_atan_dd(crtl_dd t) {
  crtl_dd u, s, one;
  int h = 0, k, invert = 0;
  one.hi = 1.0; one.lo = 0.0;
  if (t.hi > 1.0) {
    invert = 1;
    t = crtl_dd_div(one, t);
  }
  while (t.hi >= 0.0625 && h < 6) {
    u = crtl_dd_sqrt(crtl_dd_addd(crtl_dd_mul(t, t), 1.0));
    t = crtl_dd_div(t, crtl_dd_addd(u, 1.0));
    h++;
  }
  u = crtl_dd_mul(t, t);                     /* <= 2^-8 */
  s = crtl_dd_divd(one, 27.0);
  for (k = 12; k >= 0; k--) {
    s = crtl_dd_mul(u, s);
    s = crtl_dd_add(crtl_dd_divd(one, (double)(2 * k + 1)), crtl_dd_neg(s));
  }
  s = crtl_dd_mul(t, s);
  while (h > 0) { s = crtl_dd_muld(s, 2.0); h--; }   /* exact doublings */
  if (invert) s = crtl_dd_add(crtl_pio2(), crtl_dd_neg(s));
  return s;
}

double atan(double x) {
  double ax = fabs(x), r;
  crtl_dd t, w;
  if (x != x || x == 0.0) return x;
  if (isinf(x)) {
    w = crtl_pio2();
    r = w.hi + w.lo;
    return x < 0.0 ? -r : r;
  }
  t.hi = ax; t.lo = 0.0;
  w = crtl_atan_dd(t);
  r = w.hi + w.lo;
  return x < 0.0 ? -r : r;
}

/* exact-quotient dd for atan2/asin/acos: a/b with the residual captured */
static crtl_dd crtl_div_dd2(double a, double b) {
  crtl_dd n;
  n.hi = a; n.lo = 0.0;
  return crtl_dd_divd(n, b);
}

double atan2(double y, double x) {
  double r;
  crtl_dd t, w;
  int ysign = signbit(y), xsign = signbit(x);
  if (x != x || y != y) return x + y;
  if (y == 0.0) {
    if (!xsign) return y;                       /* +-0 */
    w = crtl_pi();
    r = w.hi + w.lo;
    return ysign ? -r : r;
  }
  if (x == 0.0) {
    w = crtl_pio2();
    r = w.hi + w.lo;
    return ysign ? -r : r;
  }
  if (isinf(y)) {
    if (isinf(x)) {
      w = xsign ? crtl_dd_muld(crtl_pi(), 0.75) : crtl_dd_muld(crtl_pio2(), 0.5);
    } else {
      w = crtl_pio2();
    }
    r = w.hi + w.lo;
    return ysign ? -r : r;
  }
  if (isinf(x)) {
    if (!xsign) return ysign ? crtl_bits2d(0x8000000000000000ull) : 0.0;  /* +-0 */
    w = crtl_pi();
    r = w.hi + w.lo;
    return ysign ? -r : r;
  }
  t = crtl_div_dd2(fabs(y), fabs(x));
  w = crtl_atan_dd(t);
  if (xsign) w = crtl_dd_add(crtl_pi(), crtl_dd_neg(w));
  r = w.hi + w.lo;
  return ysign ? -r : r;
}

double asin(double x) {
  double ax = fabs(x), r;
  crtl_dd p, sq, t, w;
  if (x != x) return x;
  if (ax > 1.0) return (x - x) / (x - x);       /* NaN */
  if (ax == 1.0) {
    w = crtl_pio2();
    r = w.hi + w.lo;
    return x < 0.0 ? -r : r;
  }
  if (x == 0.0) return x;
  if (ax <= 0.5) {
    p = crtl_dd_addd(crtl_dd_neg(crtl_2prod(ax, ax)), 1.0);   /* 1 - x^2 */
  } else {
    p = crtl_dd_mul(crtl_2sum(1.0, -ax), crtl_2sum(1.0, ax)); /* exact factors */
  }
  sq = crtl_dd_sqrt(p);
  t.hi = ax; t.lo = 0.0;
  w = crtl_atan_dd(crtl_dd_div(t, sq));
  r = w.hi + w.lo;
  return x < 0.0 ? -r : r;
}

double acos(double x) {
  double ax = fabs(x), r;
  crtl_dd p, sq, w;
  if (x != x) return x;
  if (ax > 1.0) return (x - x) / (x - x);       /* NaN */
  if (x == 1.0) return 0.0;
  if (x == -1.0) {
    w = crtl_pi();
    return w.hi + w.lo;
  }
  if (x == 0.0) {
    w = crtl_pio2();
    return w.hi + w.lo;
  }
  if (ax <= 0.5) {
    p = crtl_dd_addd(crtl_dd_neg(crtl_2prod(ax, ax)), 1.0);
  } else {
    p = crtl_dd_mul(crtl_2sum(1.0, -ax), crtl_2sum(1.0, ax));
  }
  sq = crtl_dd_sqrt(p);
  w = crtl_atan_dd(crtl_dd_div(sq, crtl_2sum(ax, 0.0)));
  if (x < 0.0) w = crtl_dd_add(crtl_pi(), crtl_dd_neg(w));
  return w.hi + w.lo;
}

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
float sinf(float x)   { return (float)__crtl_sin((double)x); }
float cosf(float x)   { return (float)__crtl_cos((double)x); }
float tanf(float x)   { return (float)__crtl_tan((double)x); }
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
float log2f(float x)  { return (float)__crtl_log2((double)x); }
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

/* expm1/log1p: correctly rounded on the dd kernels (the old small-threshold
   series lost ~10 digits right AT its 1e-5 cutoff). */
double expm1(double x) {
  crtl_dd a, r, s, v;
  int k, i;
  if (x != x) return x;
  if (x > 710.0)  return __crtl_exp(x);           /* +inf */
  if (x < -80.0)  return -1.0;                    /* e^x < 2^-115 */
  if (x >= -0.35 && x <= 0.35) {
    /* sum_{k>=1} x^k/k! = x * (1 + x/2 * (1 + x/3 * (...))) in dd */
    r.hi = x; r.lo = 0.0;
    s.hi = 1.0; s.lo = 0.0;
    for (i = 22; i >= 2; i--) {
      s = crtl_dd_mul(crtl_dd_divd(r, (double)i), s);
      s = crtl_dd_addd(s, 1.0);
    }
    s = crtl_dd_mul(r, s);
    return s.hi + s.lo;
  }
  a.hi = x; a.lo = 0.0;
  s = crtl_exp_core(a, &k);
  if (k > 1000) return crtl_dd_scale(s, k);       /* -1 is below half-ulp */
  v.hi = ldexp(s.hi, k);                          /* exact: k in [-116, 1000] */
  v.lo = ldexp(s.lo, k);
  v = crtl_dd_addd(v, -1.0);
  return v.hi + v.lo;
}

double log1p(double x) {
  crtl_dd w, r, one;
  if (x != x) return x;
  if (x == -1.0) return -1.0 / ((x + 1.0) * (x + 1.0));   /* -inf */
  if (x < -1.0)  return (x - x) / (x - x);        /* NaN */
  if (isinf(x))  return x;                        /* +inf */
  if (x > -6.0e-10 && x < 6.0e-10) {
    /* log(1+x) = x*(1 - x/2 + x^2/3 - x^3/4 + ...); |x| < 2^-30 so the
       dropped x^4 term is below 2^-120 relative */
    w.hi = x; w.lo = 0.0;
    one.hi = 1.0; one.lo = 0.0;
    r = crtl_dd_divd(one, 3.0);                   /* 1/3 as a dd */
    r = crtl_dd_add(r, crtl_dd_muld(w, -0.25));   /* 1/3 - x/4 */
    r = crtl_dd_mul(r, w);
    r = crtl_dd_addd(r, -0.5);                    /* -1/2 + x/3 - x^2/4 */
    r = crtl_dd_mul(r, w);
    r = crtl_dd_addd(r, 1.0);                     /* 1 - x/2 + ... */
    r = crtl_dd_mul(r, w);
    return r.hi + r.lo;
  }
  w = crtl_2sum(1.0, x);                          /* exact dd of 1+x */
  r = crtl_log_ddx(w);
  return r.hi + r.lo;
}

/* ---- correctly-rounded hyperbolics on the dd kernels -------------------- */

/* Component negate — crtl_dd_muld(v, -1.0) routes through the Dekker split,
   whose 2^27+1 scaling OVERFLOWS above ~2^996 (asinh/acosh squared args hit
   that: x ~ 2^499 -> x^2 ~ 2^998 -> NaN). Negation is exact per component. */
static crtl_dd crtl_dd_neg(crtl_dd a) {
  crtl_dd r;
  r.hi = -a.hi; r.lo = -a.lo;
  return r;
}

/* dd sqrt: hardware/Pascal Sqrt seed (correctly rounded) + one dd Newton
   correction -> ~2^-105. a must be finite, >= 0, normal-range. */
static crtl_dd crtl_dd_sqrt(crtl_dd a) {
  double y0;
  crtl_dd y, e;
  if (a.hi == 0.0) return a;
  y0 = sqrt(a.hi);
  y.hi = y0; y.lo = 0.0;
  e = crtl_dd_add(a, crtl_dd_neg(crtl_dd_mul(y, y)));  /* a - y0^2 */
  y.lo = e.hi / (2.0 * y0);
  return crtl_fast2sum(y.hi, y.lo);
}

/* e^ax and e^-ax as dds for 0 <= ax <= 40 (both scalings exact). */
static void crtl_exp_pair(double ax, crtl_dd *ep, crtl_dd *em) {
  crtl_dd a, s;
  int k;
  a.hi = ax; a.lo = 0.0;
  s = crtl_exp_core(a, &k);
  ep->hi = ldexp(s.hi, k);  ep->lo = ldexp(s.lo, k);
  a.hi = -ax;
  s = crtl_exp_core(a, &k);
  em->hi = ldexp(s.hi, k);  em->lo = ldexp(s.lo, k);
}

/* sinh as a dd for 0 <= ax <= 40 (small args by odd Taylor — the exp
   difference cancels catastrophically below ~0.35). */
static crtl_dd crtl_sinh_dd(double ax) {
  crtl_dd r, r2, s, ep, em;
  int i;
  if (ax <= 0.35) {
    /* x * (1 + x^2/(2*3) * (1 + x^2/(4*5) * (...))) */
    r.hi = ax; r.lo = 0.0;
    r2 = crtl_dd_mul(r, r);
    s.hi = 1.0; s.lo = 0.0;
    for (i = 11; i >= 1; i--) {
      s = crtl_dd_mul(crtl_dd_divd(r2, (double)(2 * i * (2 * i + 1))), s);
      s = crtl_dd_addd(s, 1.0);
    }
    return crtl_dd_mul(r, s);
  }
  crtl_exp_pair(ax, &ep, &em);
  s = crtl_dd_add(ep, crtl_dd_muld(em, -1.0));
  return crtl_dd_muld(s, 0.5);
}

static crtl_dd crtl_cosh_dd(double ax) {
  crtl_dd s, ep, em;
  crtl_exp_pair(ax, &ep, &em);
  s = crtl_dd_add(ep, em);
  return crtl_dd_muld(s, 0.5);
}

/* NOT named sinh/cosh/tanh: those collide case-insensitively with the
   Pascal routines (the b377 broken-binding landmine) — C callers come
   through the math.h function-like macros. */
double __crtl_sinh(double x) {
  double ax = fabs(x), r;
  crtl_dd s;
  int k;
  if (x != x || x == 0.0 || isinf(x)) return x;
  if (ax > 40.0) {                       /* e^-ax below dd precision */
    crtl_dd a;
    if (ax > 711.0) return x * crtl_bits2d(0x7FE0000000000000ull); /* +-inf */
    a.hi = ax; a.lo = 0.0;
    s = crtl_exp_core(a, &k);
    r = crtl_dd_scale(s, k - 1);         /* e^ax / 2 (handles overflow) */
  } else {
    s = crtl_sinh_dd(ax);
    r = s.hi + s.lo;
  }
  return x < 0.0 ? -r : r;
}

double __crtl_cosh(double x) {
  double ax = fabs(x), r;
  crtl_dd s;
  int k;
  if (x != x) return x;
  if (isinf(x)) return fabs(x);
  if (ax > 40.0) {
    crtl_dd a;
    if (ax > 711.0) return crtl_bits2d(0x7FE0000000000000ull) * 2.0; /* +inf */
    a.hi = ax; a.lo = 0.0;
    s = crtl_exp_core(a, &k);
    r = crtl_dd_scale(s, k - 1);
  } else {
    s = crtl_cosh_dd(ax);
    r = s.hi + s.lo;
  }
  return r;
}

double __crtl_tanh(double x) {
  double ax = fabs(x), r;
  crtl_dd s;
  if (x != x || x == 0.0) return x;
  if (ax > 20.0) return x < 0.0 ? -1.0 : 1.0;   /* 1 - 2e^-2ax, < half-ulp */
  s = crtl_dd_div(crtl_sinh_dd(ax), crtl_cosh_dd(ax));
  r = s.hi + s.lo;
  return x < 0.0 ? -r : r;
}

double acosh(double x) {
  crtl_dd p, w;
  if (x != x) return x;
  if (x < 1.0) return (x - x) / (x - x);          /* NaN */
  if (isinf(x)) return x;
  if (x > crtl_bits2d(0x58F0000000000000ull)) {   /* 2^400: x^2 near the Dekker-split limit */
    w = crtl_dd_add(crtl_log_dd(x), crtl_ln2());  /* log(2x) */
    return w.hi + w.lo;
  }
  p = crtl_2prod(x, x);                           /* exact x^2 as dd */
  p = crtl_dd_addd(p, -1.0);                      /* x^2-1, exact through 1 */
  w = crtl_dd_add(crtl_dd_sqrt(p), crtl_2sum(x, 0.0));
  w = crtl_log_ddx(w);
  return w.hi + w.lo;
}

double asinh(double x) {
  double ax = fabs(x), r;
  crtl_dd p, w;
  if (x != x || x == 0.0 || isinf(x)) return x;
  if (ax > crtl_bits2d(0x58F0000000000000ull)) {  /* 2^400 */
    w = crtl_dd_add(crtl_log_dd(ax), crtl_ln2()); /* log(2|x|) */
    r = w.hi + w.lo;
    return x < 0.0 ? -r : r;
  }
  p = crtl_2prod(ax, ax);
  p = crtl_dd_addd(p, 1.0);                       /* x^2+1 exact as dd */
  w = crtl_dd_add(crtl_dd_sqrt(p), crtl_2sum(ax, 0.0));
  w = crtl_log_ddx(w);
  r = w.hi + w.lo;
  return x < 0.0 ? -r : r;
}

/* Correctly-rounded hypot: scale by the larger magnitude's exponent, sum
   the exact squared dds, dd sqrt, scale back. NOT named hypot: Pascal
   Hypot (overloaded) collides — math.h maps it (the b377 landmine). */
double __crtl_hypot(double x, double y) {
  double ax = fabs(x), ay = fabs(y), t;
  unsigned long long b;
  int e;
  crtl_dd p, s;
  if (isinf(x) || isinf(y)) return crtl_bits2d(0x7FF0000000000000ull);
  if (x != x || y != y) return x + y;              /* NaN (after inf rule) */
  if (ax < ay) { t = ax; ax = ay; ay = t; }
  if (ay == 0.0) return ax;
  if (ay < ax * crtl_bits2d(0x3C30000000000000ull))  /* ay/ax < 2^-60 */
    return ax;                                       /* offset < 2^-121 rel */
  b = *(unsigned long long *)&ax;
  if ((b >> 52) == 0ull) e = -1022; else e = (int)(b >> 52) - 1023;
  ax = ldexp(ax, -e);                              /* exact, [1,2) or subnormal-lifted */
  ay = ldexp(ay, -e);                              /* >= 2^-61: exact */
  p = crtl_dd_add(crtl_2prod(ax, ax), crtl_2prod(ay, ay));
  s = crtl_dd_sqrt(p);
  return crtl_dd_scale(s, e);
}

double atanh(double x) {
  double ax = fabs(x), r;
  crtl_dd num, den, w, w2, one;
  if (x != x || x == 0.0) return x;
  if (ax > 1.0)  return (x - x) / (x - x);        /* NaN */
  if (ax == 1.0) return x / ((1.0 - ax) * (1.0 + ax));  /* +-inf */
  if (ax < 9.3e-10) {
    /* |x| < 2^-30: the (1+x)/(1-x) route computes through q ~ 1, whose
       ~2^-106 ABSOLUTE dd error becomes half-ulp RELATIVE error at the
       x-sized result. Direct odd series is relative-exact:
       x*(1 + x^2/3 + x^4/5), dropped term < 2^-180 relative. */
    w.hi = ax; w.lo = 0.0;
    w2 = crtl_dd_mul(w, w);
    one.hi = 1.0; one.lo = 0.0;
    num = crtl_dd_divd(one, 5.0);
    num = crtl_dd_mul(num, w2);
    num = crtl_dd_add(num, crtl_dd_divd(one, 3.0));
    num = crtl_dd_mul(num, w2);
    num = crtl_dd_addd(num, 1.0);
    num = crtl_dd_mul(num, w);
    r = num.hi + num.lo;
    return x < 0.0 ? -r : r;
  }
  num = crtl_2sum(1.0, ax);                       /* exact */
  den = crtl_2sum(1.0, -ax);                      /* exact */
  w = crtl_log_ddx(crtl_dd_div(num, den));
  w = crtl_dd_muld(w, 0.5);
  r = w.hi + w.lo;
  return x < 0.0 ? -r : r;
}
