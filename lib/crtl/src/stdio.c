/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: stdio — printf family + the buffered-stream veneer.
 *
 * Project-owned, libc-free. The number/format engine (__crtl_vformat) is pure
 * computation and depends on nothing but the va_list it is handed, so the
 * buffer-only entry points (vsnprintf/snprintf/sprintf/vsprintf) need no
 * syscall at all. The stream entry points (printf/fprintf/fwrite/fputs/...)
 * funnel every byte through ONE sink, __pxx_write, which is the libc-free
 * fd-write primitive the platform (PAL / Pascal RTL) provides — see
 * track-a-c-stdio-needs-pascal-import-and-data-relocs.
 *
 * STATUS (2026-06-26, master): RUNS libc-free on the current compiler. The byte
 * sink (__pxx_write/__pxx_read) resolves to the Pascal PAL via lib/rtl/pxxcio.pas;
 * stdout/stderr/stdin are real FILE objects. printf/snprintf %d/%i/%u/%x/%o/%p/
 * %c/%s/%f/%e/%g + flags/width/precision all match gcc stdout. The gating
 * blockers (va_arg-nonint, double-vararg, data-reloc, ternary-string-literal,
 * float-cast/arith) are all closed. %f/%e/%g digits come from an EXACT
 * no-libm binary->decimal engine (__crtl_dexp_*): correctly rounded at any
 * precision, honoring the C99 rounding mode (fesetround) at the cut.
 */

#include <stdarg.h>
#include <stddef.h>
#include <errno.h>
/* vsscanf below delegates numeric conversions to strtol/strtod and skips
   whitespace with isspace. Include the crtl headers (not bare externs) so the
   auto-pull links their libc-free bodies (stdlib.c / ctype.c) — otherwise they
   stay unresolved and only "work" on targets that can DT_NEEDED libc, breaking
   the static riscv32/xtensa image. */
#include <stdlib.h>
#include <ctype.h>

#ifndef EOF
#define EOF (-1)
#endif
#ifndef SEEK_SET
#define SEEK_SET 0
#endif
#ifndef SEEK_CUR
#define SEEK_CUR 1
#endif
#ifndef SEEK_END
#define SEEK_END 2
#endif

/* libc-free byte sink: write `n` bytes of `buf` to fd. Provided by the platform
   (posix syscall / ESP-IDF) the same way Pascal's RTL IO is. */
extern long __pxx_write(int fd, const void *buf, unsigned long n);
extern void *__pxx_malloc(long n);
extern void __pxx_free(void *p);
extern long __pxx_read(int fd, void *buf, unsigned long n);
extern int __pxx_open(const char *path, int flags, int mode);
extern int __pxx_close(int fd);
/* offset/return are 64-bit to match the Pascal bridge (__pxx_seek's `offset:
   Int64`) — passing a native 32-bit `long` left the high word garbage on
   riscv32 (i386/arm32 only survived because SEEK_SET's 0 whence happened to zero
   it), so seeks failed with EFAULT. File offsets are 64-bit anyway. */
extern long long __pxx_seek(int fd, long long offset, int whence);
extern int __pxx_remove(const char *path);
extern int __pxx_rename(const char *oldPath, const char *newPath);

int errno;

/* ---- FILE + the standard streams ------------------------------------------ */

struct PxxCrtlFile {
  int fd;
  int err;
  int eof;
  int heap;
  int unget;   /* one-char pushback for ungetc; -1 = empty */
};
typedef struct PxxCrtlFile FILE;

static FILE __crtl_stdin  = { 0, 0, 0, 0, -1 };
static FILE __crtl_stdout = { 1, 0, 0, 0, -1 };
static FILE __crtl_stderr = { 2, 0, 0, 0, -1 };
static FILE __crtl_files[16];

FILE *stdin  = &__crtl_stdin;
FILE *stdout = &__crtl_stdout;
FILE *stderr = &__crtl_stderr;

static FILE *__crtl_alloc_file(void) {
  int i;
  for (i = 0; i < 16; i++) {
    if (!__crtl_files[i].heap) {
      __crtl_files[i].heap = 1;
      return &__crtl_files[i];
    }
  }
  return 0;
}

/* ---- format engine -------------------------------------------------------- */

/* Unsigned -> string, MSB-first, into `out`; returns digit count. */
/* Takes unsigned long long, not unsigned long: on ILP32 a `long` is 32-bit, so a
   %llx / %llu value would be truncated on the way in (bug-crtl-printf-ll-ilp32). */
static int __crtl_utoa(char *out, unsigned long long v, int base, int upper) {
  char tmp[32];
  int n = 0, i, r;
  char d;
  if (v == 0) {
    tmp[n++] = '0';
  } else {
    while (v) {
      r = (int)(v % (unsigned long)base);
      if (r < 10) d = (char)('0' + r);
      else if (upper) d = (char)('A' + r - 10);
      else d = (char)('a' + r - 10);
      tmp[n++] = d;
      v = v / (unsigned long)base;
    }
  }
  for (i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
  return n;
}

/* ---- EXACT binary->decimal expansion of a finite double -----------------
   Every finite double is m * 2^e2 with m < 2^53, so its decimal expansion is
   finite: <= 309 integer digits and <= 1074 fraction digits. Computed with
   schoolbook decimal doubling/halving on the mantissa — no floating rounding
   anywhere, so printf digits are exact at ANY precision. This replaced the
   scaled-multiply extraction, whose product left the double's exact-integer
   range at >= 16 significant digits and printed sqrt(2)'s 16th digit as ...52
   instead of ...51 (quickjs js_dtoa round-trip search — every Math.* result
   showed a 1-ulp tail). Cost: worst case ~1.5M digit ops (subnormals);
   typical values are a few dozen halvings. */
#define CRTL_DDI 340
#define CRTL_DDF 1120
struct __crtl_dexp {
  char di[CRTL_DDI]; int ni;   /* integer part, MSB first (ni >= 1) */
  char df[CRTL_DDF]; int nf;   /* fraction part, first digit after the point */
};
static void __crtl_dexp_double(struct __crtl_dexp *x) {
  int i, c = 0, t;
  for (i = x->nf - 1; i >= 0; i--) {
    t = x->df[i] * 2 + c; x->df[i] = (char)(t % 10); c = t / 10;
  }
  while (x->nf > 0 && x->df[x->nf - 1] == 0) x->nf--;   /* strip trailing 0s */
  for (i = x->ni - 1; i >= 0; i--) {
    t = x->di[i] * 2 + c; x->di[i] = (char)(t % 10); c = t / 10;
  }
  if (c && x->ni < CRTL_DDI) {
    for (i = x->ni; i > 0; i--) x->di[i] = x->di[i - 1];
    x->di[0] = (char)c; x->ni++;
  }
}
static void __crtl_dexp_halve(struct __crtl_dexp *x) {
  int i, rem = 0, t;
  for (i = 0; i < x->ni; i++) {
    t = rem * 10 + x->di[i]; x->di[i] = (char)(t / 2); rem = t % 2;
  }
  while (x->ni > 1 && x->di[0] == 0) {                  /* strip leading 0s */
    for (i = 1; i < x->ni; i++) x->di[i - 1] = x->di[i];
    x->ni--;
  }
  for (i = 0; i < x->nf; i++) {
    t = rem * 10 + x->df[i]; x->df[i] = (char)(t / 2); rem = t % 2;
  }
  if (rem && x->nf < CRTL_DDF) x->df[x->nf++] = 5;
}
static void __crtl_dexp_init(struct __crtl_dexp *x, double a) {
  unsigned long long b, m; int be, e2, i;
  char tmp[20]; int nt = 0;
  b = *(unsigned long long *)&a;
  be = (int)((b >> 52) & 0x7FF);
  m  = b & 0xFFFFFFFFFFFFFULL;
  if (be > 0) { m |= 1ULL << 52; e2 = be - 1075; }
  else e2 = -1074;                                       /* subnormal */
  if (m == 0) { x->ni = 1; x->di[0] = 0; x->nf = 0; return; }
  nt = 0;
  while (m > 0) { tmp[nt++] = (char)(m % 10ULL); m = m / 10ULL; }
  x->ni = nt;
  for (i = 0; i < nt; i++) x->di[i] = tmp[nt - 1 - i];
  x->nf = 0;
  while (e2 > 0) { __crtl_dexp_double(x); e2--; }
  while (e2 < 0) { __crtl_dexp_halve(x); e2++; }
}
/* digit at position p, where p = 0 is the last integer digit (units), p > 0
   counts left of it, p < 0 counts fraction digits right of the point */
static int __crtl_dexp_at(const struct __crtl_dexp *x, int p) {
  if (p >= 0) { if (p >= x->ni) return 0; return x->di[x->ni - 1 - p]; }
  p = -p - 1;
  if (p >= x->nf) return 0;
  return x->df[p];
}
/* true if any nonzero digit exists strictly below position p */
static int __crtl_dexp_rest(const struct __crtl_dexp *x, int p) {
  int i;
  for (i = p - 1; i >= -x->nf; i--)
    if (__crtl_dexp_at(x, i) != 0) return 1;
  return 0;
}
/* Rounding decision at the cut, honoring the C99 rounding mode (glibc printf
   does; quickjs's toFixed probes FE_DOWNWARD/FE_TONEAREST through snprintf to
   settle ties, so ties-to-even-always broke (1.005).toFixed(2)). `neg` = value
   sign, `d` = first dropped digit, `rest` = nonzero digits beyond it, `odd` =
   last kept digit is odd. The expansion is exact, so every test is exact. */
extern int __pxx_fegetround(void);
static int __crtl_round_carry(int neg, int d, int rest, int odd) {
  int mode = __pxx_fegetround();
  if (mode == 0x400) return neg && (d > 0 || rest);     /* FE_DOWNWARD  */
  if (mode == 0x800) return (!neg) && (d > 0 || rest);  /* FE_UPWARD    */
  if (mode == 0xc00) return 0;                          /* FE_TOWARDZERO */
  if (d > 5) return 1;                                  /* FE_TONEAREST */
  if (d == 5) { if (rest) return 1; return odd; }       /* tie -> even  */
  return 0;
}

/* Extract `want` correctly rounded significant digits into dg[] (MSB first);
   *pe10 = decimal exponent of the first digit (d.ddd * 10^e form). Rounds to
   nearest; an exactly-half tail rounds the last kept digit to even (the
   expansion is exact, so the tie test is exact too). */
static void __crtl_dexp_sig(const struct __crtl_dexp *x, int want, int neg,
                            char *dg, int *pe10) {
  int hi, i, p, d, carry;
  if (x->ni == 1 && x->di[0] == 0 && x->nf == 0) {
    for (i = 0; i < want; i++) dg[i] = '0';
    *pe10 = 0; return;
  }
  if (x->ni > 1 || x->di[0] != 0) hi = x->ni - 1;
  else { hi = 0; while (hi < x->nf && x->df[hi] == 0) hi++; hi = -(hi + 1); }
  for (i = 0; i < want; i++) dg[i] = (char)('0' + __crtl_dexp_at(x, hi - i));
  p = hi - want;                                        /* first dropped pos */
  d = __crtl_dexp_at(x, p);
  carry = __crtl_round_carry(neg, d, __crtl_dexp_rest(x, p),
                             (dg[want - 1] - '0') & 1);
  for (i = want - 1; carry && i >= 0; i--) {
    if (dg[i] == '9') dg[i] = '0';
    else { dg[i]++; carry = 0; }
  }
  if (carry) { dg[0] = '1'; hi++; }                     /* 999.. -> 1000.. */
  *pe10 = hi;
}

/* IEEE double -> decimal in fixed ('f') notation with `prec` fraction digits.
   Returns the length written. Handles sign, nan, inf. Digits come from the
   exact expansion above (round-to-nearest, ties-to-even at the cut). */
static int __crtl_ftoa(char *out, double v, int prec) {
  static struct __crtl_dexp X;   /* ~1.5KB — keep off the stack */
  int n = 0, i, neg = 0, hi, p, d, carry;
  if (prec > 200) prec = 200;    /* keep the caller's fbuf bound (309+1+prec) */
  /* glibc parity: negative-signed NaN prints "-nan"; -0.0 prints "-0" */
  if (v != v) {
    if (*(unsigned long long *)&v >> 63) { out[n++] = '-'; }
    out[n++] = 'n'; out[n++] = 'a'; out[n++] = 'n';
    return n;
  }
  if (v < 0.0 || (v == 0.0 && (*(unsigned long long *)&v >> 63))) { neg = 1; v = -v; }
  if (v > 1.7976931348623157e308) {
    if (neg) out[n++] = '-';
    out[n++] = 'i'; out[n++] = 'n'; out[n++] = 'f';
    return n;
  }
  __crtl_dexp_init(&X, v);
  /* round the expansion at fraction position `prec` (position -prec) */
  p = -prec - 1;                                        /* first dropped pos */
  d = __crtl_dexp_at(&X, p);
  carry = __crtl_round_carry(neg, d, __crtl_dexp_rest(&X, p),
                             __crtl_dexp_at(&X, p + 1) & 1);
  /* apply the carry by adding 1 at position -prec (decimal add) */
  if (carry) {
    if (X.nf < prec) {               /* materialise the implicit zero tail */
      for (i = X.nf; i < prec && i < CRTL_DDF; i++) X.df[i] = 0;
      if (prec <= CRTL_DDF) X.nf = prec;
    }
    i = prec - 1;                    /* df index of position -prec */
    while (i >= 0) {
      if (X.df[i] == 9) { X.df[i] = 0; i--; }
      else { X.df[i]++; break; }
    }
    if (i < 0) {                     /* carried into the integer part */
      i = X.ni - 1;
      while (i >= 0) {
        if (X.di[i] == 9) { X.di[i] = 0; i--; }
        else { X.di[i]++; break; }
      }
      if (i < 0 && X.ni < CRTL_DDI) {
        for (i = X.ni; i > 0; i--) X.di[i] = X.di[i - 1];
        X.di[0] = 1; X.ni++;
      }
    }
  }
  if (neg) out[n++] = '-';
  hi = X.ni;
  for (i = 0; i < hi; i++) out[n++] = (char)('0' + X.di[i]);
  if (prec > 0) {
    out[n++] = '.';
    for (i = 0; i < prec; i++)
      out[n++] = (char)('0' + ((i < X.nf) ? X.df[i] : 0));
  }
  return n;
}

/* 10^k for 0 <= k <= 22, exact (see the strtod note in stdlib.c: repeated
   multiplication by 10.0 stays exact up to 1e22, and a static double table
   would trip the C global float-array init gap). */
static double __crtl_p10(int k) {
  double f = 1.0;
  while (k > 0) { f = f * 10.0; k--; }
  return f;
}

/* IEEE double -> 'g' notation: `prec` significant digits, shortest of %e/%f with
   trailing zeros stripped (the C %g rules lua's "%.14g" relies on). Returns the
   length written.

   Digit extraction is integer-based: the old repeated /10 normalisation
   accumulated rounding drift, so exact values leaked long tails
   ("100.125" printed as 100.12499999999999 at %1.15g — the cJSON red).
   Now: find the decimal exponent by COMPARING against exact powers of ten
   (the value itself is never mutated), scale once by an exact power into an
   integer mantissa of `prec` digits (one correctly-rounded op for the whole
   normal range), and expand that integer. */
static int __crtl_gtoa(char *out, double v, int prec, int upper, int force_exp) {
  static struct __crtl_dexp GX;  /* ~1.5KB — keep off the stack */
  int n = 0, i, e, neg = 0, dotpos;
  double a;
  char digits[128];
  int nd;
  /* glibc parity: negative-signed NaN prints "-nan"; -0.0 prints "-0" */
  if (v != v) {
    if (*(unsigned long long *)&v >> 63) { out[n++] = '-'; }
    out[n++] = 'n'; out[n++] = 'a'; out[n++] = 'n';
    return n;
  }
  if (prec <= 0) prec = 1;
  if (prec > 120) prec = 120;
  if (v < 0.0 || (v == 0.0 && (*(unsigned long long *)&v >> 63))) { neg = 1; a = -v; } else a = v;
  if (a > 1.7976931348623157e308) {
    if (neg) out[n++] = '-';
    out[n++] = 'i'; out[n++] = 'n'; out[n++] = 'f';
    return n;
  }
  /* exact expansion -> prec correctly rounded significant digits (see the
     __crtl_dexp engine above; the old scaled-multiply extraction was off by
     one in the 16th/17th digit — the quickjs Math.* 1-ulp tails) */
  if (a != 0.0) {
    __crtl_dexp_init(&GX, a);
    __crtl_dexp_sig(&GX, prec, neg, digits, &e);
  } else {
    for (i = 0; i < prec; i++) digits[i] = '0';
    e = 0;
  }
  nd = prec;
  if (neg) out[n++] = '-';
  if (force_exp || e < -4 || e >= prec) {
    /* exponential: d.dddde±XX. %g strips trailing mantissa zeros; %e keeps them. */
    if (!force_exp) while (nd > 1 && digits[nd - 1] == '0') nd--;
    out[n++] = digits[0];
    if (nd > 1) { out[n++] = '.'; for (i = 1; i < nd; i++) out[n++] = digits[i]; }
    out[n++] = upper ? 'E' : 'e';
    if (e < 0) { out[n++] = '-'; e = -e; } else out[n++] = '+';
    if (e < 10) out[n++] = '0';
    n += __crtl_utoa(out + n, (unsigned long)e, 10, 0);
  } else {
    /* fixed: place the decimal point after digit index e */
    dotpos = e + 1;                     /* digits before the point */
    /* strip trailing zeros that fall after the decimal point */
    while (nd > dotpos && nd > 1 && digits[nd - 1] == '0') nd--;
    if (dotpos <= 0) {
      out[n++] = '0'; out[n++] = '.';
      for (i = 0; i < -dotpos; i++) out[n++] = '0';
      for (i = 0; i < nd; i++) out[n++] = digits[i];
    } else {
      for (i = 0; i < nd; i++) {
        if (i == dotpos) out[n++] = '.';
        out[n++] = digits[i];
      }
      for (; i < dotpos; i++) out[n++] = '0';   /* integer pad if nd < dotpos */
    }
  }
  return n;
}

/* Core formatter. Writes into buf[0..cap-1] (always NUL-terminates when cap>0),
   and returns the number of chars that WOULD have been written (C99 snprintf
   semantics), so callers can detect truncation. */
static int __crtl_vformat(char *buf, size_t cap, const char *fmt, va_list ap) {
  size_t o = 0;
  int i = 0;
  char c;

  while (fmt[i]) {
    c = fmt[i++];
    if (c != '%') {
      if (o + 1 < cap) buf[o] = c;
      o++;
      continue;
    }

    /* flags */
    int left = 0, zero = 0, plus = 0, space = 0, alt = 0;
    int flagging = 1;
    while (flagging) {
      switch (fmt[i]) {
        case '-': left = 1; i++; break;
        case '0': zero = 1; i++; break;
        case '+': plus = 1; i++; break;
        case ' ': space = 1; i++; break;
        case '#': alt = 1; i++; break;
        default: flagging = 0; break;
      }
    }

    /* width (number or '*') */
    int width = 0;
    if (fmt[i] == '*') { width = va_arg(ap, int); i++; if (width < 0) { left = 1; width = -width; } }
    else while (fmt[i] >= '0' && fmt[i] <= '9') { width = width * 10 + (fmt[i] - '0'); i++; }

    /* precision (number or '*') */
    int prec = -1;
    if (fmt[i] == '.') {
      i++;
      prec = 0;
      if (fmt[i] == '*') { prec = va_arg(ap, int); i++; if (prec < 0) prec = -1; }
      else while (fmt[i] >= '0' && fmt[i] <= '9') { prec = prec * 10 + (fmt[i] - '0'); i++; }
    }

    /* length modifiers. `ll` MUST be honoured, not merely counted: on ILP32 a
       `long` is 32 bits, so reading a %llx argument with va_arg(ap, long) took
       only the low half AND left the high half in the varargs slot, which the
       NEXT conversion then consumed — one wrong value plus every later argument
       shifted (bug-crtl-printf-ll-ilp32). On LP64 long == long long, which is why
       this went unnoticed. `L` (long double) is accepted and treated as double:
       pxx models long double AS double, and a double is what the varargs slot
       carries — so %Lf/%Le/%Lg format like %f/%e/%g (c-testsuite 00204). */
    int lng = 0;
    while (fmt[i] == 'l' || fmt[i] == 'h' || fmt[i] == 'z' || fmt[i] == 'j' ||
           fmt[i] == 't' || fmt[i] == 'L') {
      if (fmt[i] == 'l') lng++;
      i++;
    }

    char k = fmt[i++];

    char num[32];
    char one[2];
    char fbuf[560];   /* %f of DBL_MAX = 309 integer digits + '.' + prec (exact engine) */
    const char *s = 0;
    int nl = 0;          /* significant length of s */
    int neg = 0;
    const char *prefix = 0;
    int preflen = 0;
    unsigned long long uv;
    long long sv;

    if (k == 'd' || k == 'i') {
      if (lng >= 2) sv = va_arg(ap, long long);
      else if (lng == 1) sv = va_arg(ap, long);
      else sv = (long long)va_arg(ap, int);
      if (sv < 0) { neg = 1; uv = (unsigned long long)(-sv); } else uv = (unsigned long long)sv;
      nl = __crtl_utoa(num, uv, 10, 0);
      s = num;
      if (neg) { prefix = "-"; preflen = 1; }
      else if (plus) { prefix = "+"; preflen = 1; }
      else if (space) { prefix = " "; preflen = 1; }
    } else if (k == 'u') {
      if (lng >= 2) uv = va_arg(ap, unsigned long long);
      else if (lng == 1) uv = va_arg(ap, unsigned long);
      else uv = (unsigned long long)va_arg(ap, unsigned int);
      nl = __crtl_utoa(num, uv, 10, 0); s = num;
    } else if (k == 'x' || k == 'X') {
      if (lng >= 2) uv = va_arg(ap, unsigned long long);
      else if (lng == 1) uv = va_arg(ap, unsigned long);
      else uv = (unsigned long long)va_arg(ap, unsigned int);
      nl = __crtl_utoa(num, uv, 16, k == 'X'); s = num;
      if (alt && uv != 0) { prefix = (k == 'X') ? "0X" : "0x"; preflen = 2; }
    } else if (k == 'o') {
      if (lng >= 2) uv = va_arg(ap, unsigned long long);
      else if (lng == 1) uv = va_arg(ap, unsigned long);
      else uv = (unsigned long long)va_arg(ap, unsigned int);
      nl = __crtl_utoa(num, uv, 8, 0); s = num;
    } else if (k == 'p') {
      uv = (unsigned long long)(unsigned long)va_arg(ap, void *);
      nl = __crtl_utoa(num, uv, 16, 0); s = num;
      prefix = "0x"; preflen = 2;
    } else if (k == 'c') {
      one[0] = (char)va_arg(ap, int); one[1] = 0; s = one; nl = 1;
    } else if (k == 's') {
      s = va_arg(ap, const char *);
      if (s == 0) s = "(null)";
      while (s[nl]) nl++;
      if (prec >= 0 && prec < nl) nl = prec;   /* precision caps a string */
    } else if (k == '%') {
      one[0] = '%'; one[1] = 0; s = one; nl = 1;
    } else if (k == 'f' || k == 'F' || k == 'e' || k == 'E' || k == 'g' || k == 'G') {
      /* float: read the double vararg (now arrives via the GP save area) and
         render. %f fixed (default prec 6); %g significant digits (default 6),
         shortest of %e/%f with trailing zeros stripped — the form lua's
         "%.14g" needs. %e shares the g path with a forced exponent prec. */
      double dv = va_arg(ap, double);
      if (k == 'g' || k == 'G') {
        nl = __crtl_gtoa(fbuf, dv, prec < 0 ? 6 : (prec == 0 ? 1 : prec), k == 'G', 0);
      } else if (k == 'e' || k == 'E') {
        /* %e: always exponential, prec+1 significant digits so the mantissa shows
           exactly `prec` fraction digits. */
        nl = __crtl_gtoa(fbuf, dv, (prec < 0 ? 6 : prec) + 1, k == 'E', 1);
      } else {
        nl = __crtl_ftoa(fbuf, dv, prec < 0 ? 6 : prec);
      }
      s = fbuf;
    } else {
      /* unknown conversion: emit verbatim */
      if (o + 1 < cap) buf[o] = '%'; o++;
      if (o + 1 < cap) buf[o] = k; o++;
      continue;
    }

    /* integer precision: minimum digit count (zero-pad the number, not the field) */
    int zpad = 0;
    if ((k=='d'||k=='i'||k=='u'||k=='x'||k=='X'||k=='o'||k=='p') && prec >= 0) {
      zero = 0;                       /* '0' flag ignored when precision given */
      if (prec > nl) zpad = prec - nl;
    }

    int bodylen = preflen + zpad + nl;
    int pad = width - bodylen;
    int p;

    /* leading spaces (right-justified, space pad) */
    if (!left && !zero) for (p = 0; p < pad; p++) { if (o + 1 < cap) buf[o] = ' '; o++; }
    /* sign / 0x prefix */
    for (p = 0; p < preflen; p++) { if (o + 1 < cap) buf[o] = prefix[p]; o++; }
    /* zero pad (field width, '0' flag) */
    if (!left && zero) for (p = 0; p < pad; p++) { if (o + 1 < cap) buf[o] = '0'; o++; }
    /* precision zeros (number minimum digits) */
    for (p = 0; p < zpad; p++) { if (o + 1 < cap) buf[o] = '0'; o++; }
    /* body */
    for (p = 0; p < nl; p++) { if (o + 1 < cap) buf[o] = s[p]; o++; }
    /* trailing spaces (left-justified) */
    if (left) for (p = 0; p < pad; p++) { if (o + 1 < cap) buf[o] = ' '; o++; }
  }

  if (cap > 0) {
    if (o < cap) buf[o] = 0; else buf[cap - 1] = 0;
  }
  return (int)o;
}

/* ---- buffer entry points (no syscall — exercisable in isolation) ---------- */

int vsnprintf(char *s, size_t n, const char *fmt, va_list ap) {
  return __crtl_vformat(s, n, fmt, ap);
}

int snprintf(char *s, size_t n, const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vformat(s, n, fmt, ap);
  va_end(ap);
  return r;
}

int vsprintf(char *s, const char *fmt, va_list ap) {
  /* no bound — use a very large cap (caller owns a big-enough buffer) */
  return __crtl_vformat(s, (size_t)-1, fmt, ap);
}

int sprintf(char *s, const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vformat(s, (size_t)-1, fmt, ap);
  va_end(ap);
  return r;
}

/* ---- stream output (rides __pxx_write) ------------------------------------ */

/* Render into a fixed stack buffer then push to the fd in one write; a line
   that does not fit re-renders into a heap buffer sized from the returned
   need (tcc dumps multi-KB preprocessed buffers through one printf). */
static int __crtl_vfdprintf(int fd, const char *fmt, va_list ap) {
  char buf[1024];
  va_list ap2;
  int n;
  va_copy(ap2, ap);
  n = __crtl_vformat(buf, sizeof(buf), fmt, ap2);
  va_end(ap2);
  if (n <= (int)sizeof(buf) - 1)
    __pxx_write(fd, buf, (unsigned long)n);
  else {
    char *p = (char *)__pxx_malloc((long)n + 1);
    if (!p) { __pxx_write(fd, buf, sizeof(buf) - 1); return n; }
    __crtl_vformat(p, (size_t)n + 1, fmt, ap);
    __pxx_write(fd, p, (unsigned long)n);
    __pxx_free(p);
  }
  return n;
}

int vfprintf(FILE *stream, const char *fmt, va_list ap) {
  return __crtl_vfdprintf(stream->fd, fmt, ap);
}

int vprintf(const char *fmt, va_list ap) {
  return __crtl_vfdprintf(1, fmt, ap);
}

int fprintf(FILE *stream, const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vfdprintf(stream->fd, fmt, ap);
  va_end(ap);
  return r;
}

int printf(const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vfdprintf(1, fmt, ap);
  va_end(ap);
  return r;
}

/* ---- byte / string stream API (what lua's lua_writestring etc. call) ------ */

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
  unsigned long total = (unsigned long)size * (unsigned long)nmemb;
  long w;
  if (total == 0) return 0;
  w = __pxx_write(stream->fd, ptr, total);
  if (w <= 0) { stream->err = 1; return 0; }
  if (size == 0) return 0;
  return (size_t)((unsigned long)w / (unsigned long)size);
}

int fputs(const char *s, FILE *stream) {
  unsigned long n = 0;
  while (s[n]) n++;
  if (__pxx_write(stream->fd, s, n) < 0) { stream->err = 1; return -1; }
  return (int)n;
}

int puts(const char *s) {
  unsigned long n = 0;
  while (s[n]) n++;
  if (__pxx_write(1, s, n) < 0) return -1;
  if (__pxx_write(1, "\n", 1) < 0) return -1;
  return (int)n + 1;
}

int fputc(int c, FILE *stream) {
  char ch = (char)c;
  if (__pxx_write(stream->fd, &ch, 1) < 0) { stream->err = 1; return -1; }
  return c & 0xFF;
}

int putc(int c, FILE *stream) { return fputc(c, stream); }

int putchar(int c) {
  char ch = (char)c;
  if (__pxx_write(1, &ch, 1) < 0) return -1;
  return c & 0xFF;
}

/* ---- input (rides __pxx_read) --------------------------------------------- */

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
  unsigned long total = (unsigned long)size * (unsigned long)nmemb;
  unsigned long got = 0;
  long r;
  if (total == 0) return 0;
  if (stream->unget >= 0) {           /* honor a pending ungetc pushback */
    ((unsigned char *)ptr)[0] = (unsigned char)stream->unget;
    stream->unget = -1;
    got = 1;
    if (total == 1) { if (size == 0) return 0; return (size_t)(got / (unsigned long)size); }
  }
  r = __pxx_read(stream->fd, (unsigned char *)ptr + got, total - got);
  if (r <= 0) {
    if (got == 0) { stream->eof = 1; return 0; }
    r = 0;                            /* pushback byte still counts */
  }
  got += (unsigned long)r;
  if (size == 0) return 0;
  return (size_t)(got / (unsigned long)size);
}

int fgetc(FILE *stream) {
  unsigned char ch;
  long r;
  if (stream->unget >= 0) {           /* pending pushback (see ungetc) */
    int c = stream->unget;
    stream->unget = -1;
    return c;
  }
  r = __pxx_read(stream->fd, &ch, 1);
  if (r <= 0) { stream->eof = 1; return -1; }
  return (int)ch;
}

/* Push one char back so the next fgetc returns it (single-level, per C). EOF is
   a no-op. lua's chunk loader uses getc/ungetc to peek/skip a leading '#!' or
   BOM. */
int ungetc(int c, FILE *stream) {
  if (c < 0 || !stream) return -1;
  stream->unget = (unsigned char)c;
  stream->eof = 0;
  return (unsigned char)c;
}

int getc(FILE *stream) { return fgetc(stream); }

int getchar(void) { return fgetc(&__crtl_stdin); }

char *fgets(char *s, int n, FILE *stream) {
  int i = 0;
  unsigned char ch;
  if (n <= 0) return 0;
  while (i < n - 1) {
    long r = __pxx_read(stream->fd, &ch, 1);
    if (r <= 0) { stream->eof = 1; break; }
    s[i++] = (char)ch;
    if (ch == '\n') break;
  }
  if (i == 0) return 0;
  s[i] = 0;
  return s;
}

/* ---- file open / positioning --------------------------------------------- */

#define CRTL_O_RDONLY 0
#define CRTL_O_WRONLY 1
#define CRTL_O_RDWR   2
#define CRTL_O_CREAT  64
#define CRTL_O_TRUNC  512
#define CRTL_O_APPEND 1024

static int __crtl_mode_flags(const char *mode, int *flags) {
  int plus = 0;
  const char *p;
  if (!mode || !mode[0]) return -1;
  for (p = mode + 1; *p; p++) if (*p == '+') plus = 1;
  if (mode[0] == 'r') {
    *flags = plus ? CRTL_O_RDWR : CRTL_O_RDONLY;
    return 0;
  }
  if (mode[0] == 'w') {
    *flags = (plus ? CRTL_O_RDWR : CRTL_O_WRONLY) | CRTL_O_CREAT | CRTL_O_TRUNC;
    return 0;
  }
  if (mode[0] == 'a') {
    *flags = (plus ? CRTL_O_RDWR : CRTL_O_WRONLY) | CRTL_O_CREAT | CRTL_O_APPEND;
    return 0;
  }
  return -1;
}

FILE *fopen(const char *path, const char *mode) {
  int flags, fd;
  FILE *f;
  if (__crtl_mode_flags(mode, &flags) < 0) { errno = EINVAL; return 0; }
  fd = __pxx_open(path, flags, 438);
  if (fd < 0) { errno = -fd; return 0; }
  f = __crtl_alloc_file();
  if (!f) { __pxx_close(fd); errno = ENOMEM; return 0; }
  f->fd = fd;
  f->err = 0;
  f->eof = 0;
  f->unget = -1;
  return f;
}

/* fdopen: wrap an already-open descriptor; mode only validated (the fd's
   own open flags govern I/O). tcc writes its output ELF via fdopen(fd,"wb"). */
FILE *fdopen(int fd, const char *mode) {
  int flags;
  FILE *f;
  if (fd < 0 || __crtl_mode_flags(mode, &flags) < 0) { errno = EINVAL; return 0; }
  f = __crtl_alloc_file();
  if (!f) { errno = ENOMEM; return 0; }
  f->fd = fd;
  f->err = 0;
  f->eof = 0;
  f->unget = -1;
  return f;
}

int fileno(FILE *stream) {
  if (!stream) { errno = EINVAL; return -1; }
  return stream->fd;
}

FILE *freopen(const char *path, const char *mode, FILE *stream) {
  int flags, fd;
  if (!stream) { errno = EINVAL; return 0; }
  if (__crtl_mode_flags(mode, &flags) < 0) { errno = EINVAL; return 0; }
  fd = __pxx_open(path, flags, 438);
  if (fd < 0) { errno = -fd; stream->err = 1; return 0; }
  if (stream->fd >= 0) __pxx_close(stream->fd);
  stream->fd = fd;
  stream->err = 0;
  stream->eof = 0;
  stream->unget = -1;
  return stream;
}

int fclose(FILE *stream) {
  int rc;
  if (!stream) { errno = EINVAL; return -1; }
  rc = __pxx_close(stream->fd);
  stream->fd = -1;
  stream->err = 0;
  stream->eof = 0;
  if (stream->heap) stream->heap = 0;
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

int fseek(FILE *stream, long off, int whence) {
  long r;
  if (!stream) { errno = EINVAL; return -1; }
  r = __pxx_seek(stream->fd, off, whence);
  if (r < 0) { errno = -r; stream->err = 1; return -1; }
  stream->eof = 0;
  return 0;
}

long ftell(FILE *stream) {
  long r;
  if (!stream) { errno = EINVAL; return -1; }
  r = __pxx_seek(stream->fd, 0, SEEK_CUR);
  if (r < 0) { errno = -r; stream->err = 1; return -1; }
  return r;
}

void rewind(FILE *stream) {
  if (stream) {
    if (__pxx_seek(stream->fd, 0, SEEK_SET) < 0) stream->err = 1;
    else stream->eof = 0;
  }
}

FILE *tmpfile(void) { errno = EINVAL; return 0; }
char *tmpnam(char *s) { (void)s; errno = EINVAL; return 0; }
int remove(const char *path) { int rc = __pxx_remove(path); if (rc < 0) { errno = -rc; return -1; } return 0; }
int rename(const char *oldp, const char *newp) { int rc = __pxx_rename(oldp, newp); if (rc < 0) { errno = -rc; return -1; } return 0; }

int close(int fd) { int rc = __pxx_close(fd); if (rc < 0) { errno = -rc; return -1; } return 0; }
long lseek(int fd, long offset, int whence) { long r = __pxx_seek(fd, offset, whence); if (r < 0) { errno = -r; return -1; } return r; }
long read(int fd, void *buf, unsigned long count) { long r = __pxx_read(fd, buf, count); if (r < 0) { errno = -r; return -1; } return r; }
long write(int fd, const void *buf, unsigned long count) { long r = __pxx_write(fd, buf, count); if (r < 0) { errno = -r; return -1; } return r; }

/* Positioned I/O — no PAL pread/pwrite syscall, so emulate offset-preserving:
   save the current offset, seek to `off`, do the read/write, restore. POSIX
   requires pread/pwrite to leave the file offset unchanged; sqlite's USE_PREAD
   path (os_unix seekAndRead/seekAndWrite) calls these directly. Not atomic wrt
   concurrent access, but crtl sqlite runs SQLITE_THREADSAFE=0 / single-fd. */
long pread(int fd, void *buf, unsigned long count, long off) {
  long cur = __pxx_seek(fd, 0, 1 /* SEEK_CUR */);
  if (cur < 0) { errno = -cur; return -1; }
  long s = __pxx_seek(fd, off, 0 /* SEEK_SET */);
  if (s < 0) { errno = -s; return -1; }
  long r = __pxx_read(fd, buf, count);
  __pxx_seek(fd, cur, 0);
  if (r < 0) { errno = -r; return -1; }
  return r;
}
long pwrite(int fd, const void *buf, unsigned long count, long off) {
  long cur = __pxx_seek(fd, 0, 1 /* SEEK_CUR */);
  if (cur < 0) { errno = -cur; return -1; }
  long s = __pxx_seek(fd, off, 0 /* SEEK_SET */);
  if (s < 0) { errno = -s; return -1; }
  long r = __pxx_write(fd, buf, count);
  __pxx_seek(fd, cur, 0);
  if (r < 0) { errno = -r; return -1; }
  return r;
}

/* ---- buffering / status (unbuffered model: no-ops) ------------------------ */

int fflush(FILE *stream) { (void)stream; return 0; }
int feof(FILE *stream) { return stream->eof; }
int ferror(FILE *stream) { return stream->err; }
void clearerr(FILE *stream) { stream->err = 0; stream->eof = 0; }
int setvbuf(FILE *stream, char *buf, int mode, size_t size) { (void)stream; (void)buf; (void)mode; (void)size; return 0; }
void setbuf(FILE *stream, char *buf) { (void)stream; (void)buf; }

/* ---- minimal sscanf ------------------------------------------------------- */
/* Enough for cJSON's number-roundtrip check (`sscanf(buf, "%lg", &d)`) plus the
   common integer/string conversions, so a real C library that scans strings can
   build and run libc-free. Supported: leading-whitespace skipping, literal
   character match, and the conversions %d/%i/%u/%x/%o (with l/ll length →
   long/long long), %f/%e/%g (with l/L length → double, else float), %s
   (whitespace-delimited, NUL-terminated), %c (single char), and %%. Field width
   and the '*' assignment-suppression flag are NOT supported (cJSON uses neither).
   Numeric conversions delegate to strtol/strtod for correctness. Returns the
   number of input items successfully assigned (C sscanf semantics). */
int vsscanf(const char *s, const char *fmt, va_list ap) {
  int count = 0;
  const char *p = fmt;
  while (*p) {
    if (isspace((unsigned char)*p)) {
      while (isspace((unsigned char)*s)) s++;
      p++;
      continue;
    }
    if (*p != '%') {
      if (*s != *p) break;
      s++; p++;
      continue;
    }
    p++; /* past '%' */
    {
      int lng = 0;
      char conv;
      while (*p == 'l' || *p == 'L' || *p == 'h') {
        if (*p == 'l' || *p == 'L') lng++;
        p++;
      }
      conv = *p;
      if (conv == '\0') break;
      p++;
      if (conv != 'c' && conv != '%')
        while (isspace((unsigned char)*s)) s++;
      if (conv == 'd' || conv == 'i' || conv == 'u' || conv == 'x' || conv == 'o') {
        char *end;
        int base = (conv == 'x') ? 16 : (conv == 'o') ? 8 : 10;
        long v = strtol(s, &end, base);
        if (end == s) break;
        if (lng >= 2) *va_arg(ap, long long *) = (long long)v;
        else if (lng == 1) *va_arg(ap, long *) = v;
        else *va_arg(ap, int *) = (int)v;
        s = end; count++;
      } else if (conv == 'f' || conv == 'e' || conv == 'g' ||
                 conv == 'F' || conv == 'E' || conv == 'G') {
        char *end;
        double v = strtod(s, &end);
        if (end == s) break;
        if (lng >= 1) *va_arg(ap, double *) = v;
        else *va_arg(ap, float *) = (float)v;
        s = end; count++;
      } else if (conv == 's') {
        char *dst = va_arg(ap, char *);
        if (*s == '\0') break;
        while (*s && !isspace((unsigned char)*s)) *dst++ = *s++;
        *dst = '\0'; count++;
      } else if (conv == 'c') {
        char *dst = va_arg(ap, char *);
        if (*s == '\0') break;
        *dst = *s++; count++;
      } else if (conv == '%') {
        if (*s != '%') break;
        s++;
      } else {
        break; /* unsupported conversion: stop, matching glibc's early return */
      }
    }
  }
  return count;
}

int sscanf(const char *s, const char *fmt, ...) {
  va_list ap;
  int r;
  va_start(ap, fmt);
  r = vsscanf(s, fmt, ap);
  va_end(ap);
  return r;
}
