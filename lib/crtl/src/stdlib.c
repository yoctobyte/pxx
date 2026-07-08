/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: stdlib — allocator + process control + small helpers.
 *
 * Project-owned, libc-free. malloc/free/realloc/calloc ride the SAME mmap-backed
 * pool as the Pascal RTL heap, via the pxxcio bridge (__pxx_malloc/_free/_realloc
 * -> PXXAlloc/PXXFree/PXXRealloc). One heap shared with Pascal; PXXAlloc returns
 * zeroed memory so calloc needs no extra clear. The bridge self-inits lazily, so
 * no startup hook is required.
 */

#include <stddef.h>
#include <string.h>
#include <stdlib.h>

extern void *__pxx_malloc(long n);
extern void  __pxx_free(void *p);
extern void *__pxx_realloc(void *p, long n);
extern void  __pxx_exit(int code);

/* ---- heap ----------------------------------------------------------------- */

void *malloc(size_t size) { return __pxx_malloc((long)size); }
void  free(void *ptr)     { __pxx_free(ptr); }
void *realloc(void *ptr, size_t size) { return __pxx_realloc(ptr, (long)size); }

void *calloc(size_t count, size_t size) {
  /* PXXAlloc already zeroes; just guard the multiply overflow. */
  size_t total = count * size;
  if (size != 0 && total / size != count) return 0;   /* overflow */
  return __pxx_malloc((long)total);
}

void *reallocarray(void *ptr, size_t nmemb, size_t size) {
  size_t total = nmemb * size;
  if (size != 0 && total / size != nmemb) return 0;
  return __pxx_realloc(ptr, (long)total);
}

/* ---- process control ------------------------------------------------------ */

void exit(int code)  { __pxx_exit(code); }
void _Exit(int code) { __pxx_exit(code); }
void abort(void)     { __pxx_exit(134); }   /* 128 + SIGABRT(6) */

/* ---- environment / conversions -------------------------------------------- */

char *getenv(const char *name) { (void)name; return 0; }   /* no environment yet */

int abs(int v) { return v < 0 ? -v : v; }
long labs(long v) { return v < 0 ? -v : v; }

int atoi(const char *s) {
  int sign = 1, v = 0;
  if (!s) return 0;
  while (*s == ' ' || *s == '\t' || *s == '\n') s++;
  if (*s == '-') { sign = -1; s++; } else if (*s == '+') s++;
  while (*s >= '0' && *s <= '9') { v = v * 10 + (*s - '0'); s++; }
  return v * sign;
}

/* No symlink/./.. resolution — identity copy (absolute input assumed). Enough
   for tcc's include-path canonicalisation; a real walk needs readlink. */
char *realpath(const char *path, char *resolved) {
  size_t n;
  if (!path) return 0;
  n = strlen(path);
  if (!resolved) {
    resolved = (char *)malloc(n + 1);
    if (!resolved) return 0;
  }
  memcpy(resolved, path, n + 1);
  return resolved;
}

long atol(const char *s) {
  long sign = 1, v = 0;
  if (!s) return 0;
  while (*s == ' ' || *s == '\t' || *s == '\n') s++;
  if (*s == '-') { sign = -1; s++; } else if (*s == '+') s++;
  while (*s >= '0' && *s <= '9') { v = v * 10 + (*s - '0'); s++; }
  return v * sign;
}

long strtol(const char *s, char **end, int base) {
  long sign = 1, v = 0;
  const char *p = s;
  if (!p) { if (end) *end = (char *)s; return 0; }
  while (*p == ' ' || *p == '\t' || *p == '\n') p++;
  if (*p == '-') { sign = -1; p++; } else if (*p == '+') p++;
  if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { p += 2; base = 16; }
  if (base == 0) base = 10;
  for (;;) {
    int d;
    char c = *p;
    if (c >= '0' && c <= '9') d = c - '0';
    else if (c >= 'a' && c <= 'z') d = c - 'a' + 10;
    else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10;
    else break;
    if (d >= base) break;
    v = v * base + d; p++;
  }
  if (end) *end = (char *)p;
  return v * sign;
}

unsigned long strtoul(const char *s, char **end, int base) {
  return (unsigned long)strtol(s, end, base);
}

/* 10^k for 0 <= k <= 22: every value is exactly representable in a double,
   and each step's product is too, so repeated multiplication stays EXACT
   (no table needed — a static double array would also trip the C global
   float-array init gap). */
static double __crtl_pow10e(int k) {
  double f = 1.0;
  while (k > 0) { f = f * 10.0; k--; }
  return f;
}

/* strtod: parse [sign] digits [. digits] [ (e|E) [sign] digits ]. No hex floats,
   no inf/nan literals (lua's lexer handles those itself before calling).

   Precision: the old implementation accumulated the fraction as
   digit * 0.1^k — 0.1 is inexact, so short exact values drifted by 1 ulp
   ("0.0625" parsed to 0.062500000000000008; cJSON round-trips went red and a
   tcc-by-pxx rodata constant differed from gcc). Now the mantissa is read as
   one integer and scaled by an exact power of ten (Clinger's fast path): for
   mantissa < 2^53 and |decimal exponent| <= 22 — every literal in the
   corpora — the single multiply/divide is correctly rounded, matching glibc
   bit-for-bit. Longer mantissas keep collecting into the integer (rounded
   once at bit 53+) and larger exponents scale in exact 1e22 chunks; those
   can be 1 ulp off, same class as before but strictly no worse. */
double strtod(const char *s, char **end) {
  const char *p = s;
  double v, sign = 1.0;
  unsigned long long mant = 0;
  int any = 0, dexp = 0;
  if (!p) { if (end) *end = (char *)s; return 0.0; }
  while (*p == ' ' || *p == '\t' || *p == '\n') p++;
  if (*p == '-') { sign = -1.0; p++; } else if (*p == '+') p++;
  while (*p >= '0' && *p <= '9') {
    if (mant < 1000000000000000000ULL) mant = mant * 10ULL + (unsigned long long)(*p - '0');
    else dexp++;                    /* >19 digits: keep magnitude, drop digit */
    p++; any = 1;
  }
  if (*p == '.') {
    p++;
    while (*p >= '0' && *p <= '9') {
      if (mant < 1000000000000000000ULL) {
        mant = mant * 10ULL + (unsigned long long)(*p - '0');
        dexp--;
      }                             /* excess fraction digits: truncate */
      p++; any = 1;
    }
  }
  if (any && (*p == 'e' || *p == 'E')) {
    int esign = 1, e = 0;
    const char *ep = p + 1;
    if (*ep == '-') { esign = -1; ep++; } else if (*ep == '+') ep++;
    if (*ep >= '0' && *ep <= '9') {
      while (*ep >= '0' && *ep <= '9') {
        if (e < 100000) e = e * 10 + (*ep - '0');
        ep++;
      }
      p = ep;
      if (esign < 0) dexp -= e; else dexp += e;
    }
  }
  v = (double)mant;
  if (v != 0.0) {
    while (dexp > 22)  { v = v * 1e22; dexp -= 22; }   /* 1e22 exact */
    while (dexp < -22) { v = v / 1e22; dexp += 22; }
    if (dexp > 0) v = v * __crtl_pow10e(dexp);
    else if (dexp < 0) v = v / __crtl_pow10e(-dexp);
  }
  if (end) *end = (char *)(any ? p : s);
  return sign * v;
}

/* system(): the libc-free runtime has no command processor. Per C, system(NULL)
   queries availability — return 0 (none). A real command returns -1 (failure).
   lua's os.execute links this but the test scripts never shell out. */
int system(const char *command) {
  if (command == 0) return 0;
  return -1;
}

/* ---- qsort (insertion sort — simple, stable enough for lua's small uses) --- */

static void __crtl_swap(char *a, char *b, size_t n) {
  size_t i;
  for (i = 0; i < n; i++) { char t = a[i]; a[i] = b[i]; b[i] = t; }
}

void qsort(void *base, size_t nmemb, size_t size,
           int (*cmp)(const void *, const void *)) {
  char *a = (char *)base;
  size_t i, j;
  for (i = 1; i < nmemb; i++) {
    for (j = i; j > 0; j--) {
      char *cur = a + j * size;
      char *prv = a + (j - 1) * size;
      if (cmp(prv, cur) <= 0) break;
      __crtl_swap(prv, cur, size);
    }
  }
}

/* ---- minimal time (seed only) --------------------------------------------- */
/* lua uses time(NULL) only to seed its hash; a constant is correct-but-fixed.
   A real clock bridge (PAL monotonic) is a follow-up. */
typedef long __crtl_time_t;
__crtl_time_t time(__crtl_time_t *t) { if (t) *t = 0; return 0; }

/* long double == double in pxx: strtold forwards to strtod. */
double strtold(const char *s, char **end) { return strtod(s, end); }
