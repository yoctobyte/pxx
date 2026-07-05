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

/* strtod: parse [sign] digits [. digits] [ (e|E) [sign] digits ]. No hex floats,
   no inf/nan literals (lua's lexer handles those itself before calling). */
double strtod(const char *s, char **end) {
  const char *p = s;
  double v = 0.0, sign = 1.0;
  int any = 0;
  if (!p) { if (end) *end = (char *)s; return 0.0; }
  while (*p == ' ' || *p == '\t' || *p == '\n') p++;
  if (*p == '-') { sign = -1.0; p++; } else if (*p == '+') p++;
  while (*p >= '0' && *p <= '9') { v = v * 10.0 + (double)(*p - '0'); p++; any = 1; }
  if (*p == '.') {
    double scale = 0.1;
    p++;
    while (*p >= '0' && *p <= '9') { v = v + (double)(*p - '0') * scale; scale = scale * 0.1; p++; any = 1; }
  }
  if (any && (*p == 'e' || *p == 'E')) {
    int esign = 1, e = 0;
    const char *ep = p + 1;
    if (*ep == '-') { esign = -1; ep++; } else if (*ep == '+') ep++;
    if (*ep >= '0' && *ep <= '9') {
      while (*ep >= '0' && *ep <= '9') { e = e * 10 + (*ep - '0'); ep++; }
      p = ep;
      double f = 1.0, ten = 10.0;
      int n = e;
      while (n > 0) { f = f * ten; n--; }
      if (esign < 0) v = v / f; else v = v * f;
    }
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

/* typedef'd compare pointer — an INLINE `int (*cmp)(...)` param does not yet
   capture its signature in the C frontend, so calling it errors "undeclared
   function". The typedef form does (see cfnptr). */
typedef int (*__crtl_cmpfn)(const void *, const void *);

void qsort(void *base, size_t nmemb, size_t size, __crtl_cmpfn cmp) {
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
