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
#include <inttypes.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
#include <inttypes.h>

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

/* The environment, read once from /proc/self/environ — the same source (and
   the same reasoning) as the Pascal RTL's sysutils.EnvLoad: the records are
   NUL-separated, so this is not text, and a failed open leaves the table empty
   so every lookup answers "unset" rather than erroring. A program that cannot
   see its environment should behave like one started without one.

   Was `return 0` with the comment "no environment yet", which meant C code
   compiled by pxx silently saw an empty environment — configuration read
   through getenv() just never took effect. */
extern int __pxx_open(const char *path, int flags, int mode);
extern long __pxx_read(int fd, void *buf, unsigned long n);
extern int __pxx_close(int fd);

#define PXX_ENV_BUFSZ 16384

static char pxx_env_buf[PXX_ENV_BUFSZ];
static long pxx_env_len = 0;
static int pxx_env_loaded = 0;

static void pxx_env_load(void) {
  int fd;
  long got;
  if (pxx_env_loaded) return;
  pxx_env_loaded = 1;
  fd = __pxx_open("/proc/self/environ", 0, 0);   /* O_RDONLY */
  if (fd < 0) return;
  got = __pxx_read(fd, pxx_env_buf, PXX_ENV_BUFSZ);
  __pxx_close(fd);
  if (got > 0) pxx_env_len = got;
}

char *getenv(const char *name) {
  long i = 0;
  if (!name || !*name) return 0;
  pxx_env_load();
  while (i < pxx_env_len) {
    /* one NUL-terminated "NAME=VALUE" record at pxx_env_buf[i] */
    long j = 0;
    while (name[j] && pxx_env_buf[i + j] == name[j]) j++;
    if (!name[j] && pxx_env_buf[i + j] == '=')
      return &pxx_env_buf[i + j + 1];
    while (i < pxx_env_len && pxx_env_buf[i]) i++;
    i++;                                        /* past the NUL */
  }
  return 0;
}

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

/* strtol/strtoul now DELEGATE to the 64-bit pair and clamp to long's range.
   They used to accumulate on their own, which had two defects the file's own
   note below already described but left standing for these two:

     strtol("99999999999999999999", 0, 10)  ->  7766279631452241919
       (silently WRAPPED, where C requires LONG_MAX and errno = ERANGE)
     strtol("010", 0, 0)                    ->  10, not 8
       (base 0 means a leading '0' is octal)

   The note reasoned the overflow was masked because `long` is 64-bit on this
   LP64 target and strtol's callers had not reached it — but the input above
   reaches it on any target, and a silently wrapped value is exactly the
   plausible-wrong-number this codebase treats as worse than an error. strtoul
   was worse again: it cast the SIGNED result, so it inherited the wrap and
   could not represent the upper half of its own range.

   On LP64 the clamp below is a no-op and ERANGE comes from the 64-bit callee;
   on i386/arm32, where long is 32 bits, the clamp is what does the work. */
long strtol(const char *s, char **end, int base) {
  long long v = strtoll(s, end, base);
  if (v > (long long)LONG_MAX) { errno = ERANGE; return LONG_MAX; }
  if (v < (long long)LONG_MIN) { errno = ERANGE; return LONG_MIN; }
  return (long)v;
}

unsigned long strtoul(const char *s, char **end, int base) {
  unsigned long long v = strtoull(s, end, base);
  if (v > (unsigned long long)ULONG_MAX) { errno = ERANGE; return ULONG_MAX; }
  return (unsigned long)v;
}

/* strtoll/strtoull/atoll were declared in stdlib.h (C99) but, until now, never
   defined. Nothing called them, so the gap was invisible: the C frontend's
   unresolved-extern fallback (any prototype with no in-tree body defaults to a
   dynamic `libc.so.6` import, compiler/cparser.inc CPullCrtlForPrototypes) let
   the program "link" anyway. On i386 that silently turned a self-contained
   static executable into a broken hybrid static+dynamic one (adding PT_INTERP/
   PT_DYNAMIC for a symbol nothing at runtime even calls) whose exit code came
   back ASLR-dependent garbage while stdout stayed correct — the exact shape of
   bug-c-i386-crtl-growth-corrupts-main-exit-code. sscanf's field-width fix
   (ea07b041c) was the first real caller, via its 64-bit numeric conversion.

   Not simple forwards to strtol/strtoul: those don't clamp on overflow or
   auto-detect an octal `0` prefix for base 0, and the gcc oracle (below)
   checks both — 64-bit range makes overflow reachable with an ordinary
   literal ("9223372036854775808") in a way `long` on this LP64 target masks
   for strtol's own callers so far. */
long long strtoll(const char *s, char **end, int base) {
  long long sign = 1, v = 0;
  const char *p = s;
  const char *digStart;
  int overflow = 0, sawPrefix = 0;
  if (!p) { if (end) *end = (char *)s; return 0; }
  while (*p == ' ' || *p == '\t' || *p == '\n') p++;
  if (*p == '-') { sign = -1; p++; } else if (*p == '+') p++;
  if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { p += 2; base = 16; sawPrefix = 1; }
  else if (base == 0 && p[0] == '0') { base = 8; }
  if (base == 0) base = 10;
  digStart = p;
  for (;;) {
    int d;
    char c = *p;
    if (c >= '0' && c <= '9') d = c - '0';
    else if (c >= 'a' && c <= 'z') d = c - 'a' + 10;
    else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10;
    else break;
    if (d >= base) break;
    if (!overflow) {
      if (v > (9223372036854775807LL - d) / base) overflow = 1;
      else v = v * base + d;
    }
    p++;
  }
  /* No digits => no conversion (C99 7.20.1.4p7): value 0 and endptr back at the
     ORIGINAL string, not wherever whitespace/sign parsing left it. The `0x`
     case is not "no conversion" though — the longest VALID prefix of "0x" is
     "0", so the value is 0 and endptr points at the 'x'. Consuming the whole
     "0x" made a caller scanning `0xg` skip a character it had not converted. */
  if (p == digStart) {
    if (sawPrefix) p = digStart - 1;
    else { if (end) *end = (char *)s; return 0; }
  }
  if (end) *end = (char *)p;
  if (overflow) {
    errno = ERANGE;            /* C requires it; callers distinguish clamp from a real value */
    return sign < 0 ? (-9223372036854775807LL - 1) : 9223372036854775807LL;
  }
  return v * sign;
}

unsigned long long strtoull(const char *s, char **end, int base) {
  unsigned long long v = 0;
  const char *p = s;
  const char *digStart;
  int neg = 0, overflow = 0, sawPrefix = 0;
  if (!p) { if (end) *end = (char *)s; return 0; }
  while (*p == ' ' || *p == '\t' || *p == '\n') p++;
  if (*p == '-') { neg = 1; p++; } else if (*p == '+') p++;
  if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { p += 2; base = 16; sawPrefix = 1; }
  else if (base == 0 && p[0] == '0') { base = 8; }
  if (base == 0) base = 10;
  digStart = p;
  for (;;) {
    int d;
    char c = *p;
    if (c >= '0' && c <= '9') d = c - '0';
    else if (c >= 'a' && c <= 'z') d = c - 'a' + 10;
    else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10;
    else break;
    if (d >= base) break;
    if (!overflow) {
      if (v > (18446744073709551615ULL - (unsigned long long)d) / (unsigned long long)base) overflow = 1;
      else v = v * (unsigned long long)base + (unsigned long long)d;
    }
    p++;
  }
  if (p == digStart) {          /* see the note in strtoll */
    if (sawPrefix) p = digStart - 1;
    else { if (end) *end = (char *)s; return 0; }
  }
  if (end) *end = (char *)p;
  if (overflow) { errno = ERANGE; return 18446744073709551615ULL; }
  /* C99 7.20.1.4p4: a leading '-' negates in unsigned arithmetic, not an
     error — strtoull("-1", ...) is ULLONG_MAX, same as glibc. */
  return neg ? (0ULL - v) : v;
}

long long atoll(const char *s) {
  return strtoll(s, (char **)0, 10);
}

/* <inttypes.h>'s greatest-width conversions (imaxabs/imaxdiv/strtoimax/
   strtoumax) used to live here. They now live in their header's sibling impl,
   src/inttypes.c — a header's functions MUST be in its own .c or the crtl
   auto-pull cannot find them (see that file's note). */

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
/* hex digit value, or -1 */
static int __crtl_hexval(int c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

/* m * 2^e, saturating at the ends the way ldexp does.

   ONLY 2.0 and 0.5 are used as factors. The obvious optimisation -- stepping in
   chunks of 2^1023 via a decimal constant like 8.98846567431158e307 -- makes
   the result depend on that literal being correctly rounded, and it was off by
   enough to flush 0x1p-1074 (the smallest subnormal) to ZERO instead of
   producing it. 2.0 and 0.5 are exact in every rounding mode, and halving a
   power of two stays exact all the way down through the subnormal range, so
   this reaches 2^-1074 precisely. At most ~2100 iterations, which is nothing
   next to being wrong.

   (The literal in question is a known issue in its own right:
   bug-a-float-literal-lexer-is-not-correctly-rounded.) */
static double __crtl_ldexp_ull(unsigned long long m, int e) {
  double v = (double)m;
  if (v == 0.0) return 0.0;
  while (e > 0) {
    v *= 2.0; e--;
    if (v > 1.7976931348623157e308) return v;      /* inf: stop, it is stable */
  }
  while (e < 0) {
    v *= 0.5; e++;
    if (v == 0.0) return 0.0;                      /* underflowed to zero */
  }
  return v;
}

double strtod(const char *s, char **end) {
  const char *p = s;
  double v, sign = 1.0;
  unsigned long long mant = 0;
  int any = 0, dexp = 0;
  if (!p) { if (end) *end = (char *)s; return 0.0; }
  while (*p == ' ' || *p == '\t' || *p == '\n') p++;
  if (*p == '-') { sign = -1.0; p++; } else if (*p == '+') p++;

  /* C99 hex float: 0x h* [. h*] [pP [+-] d+]. Missing entirely until
     2026-08-05, so strtod("0x1.8p+1") returned 0 leaving "x1.8p+1" — and with
     it atof, scanf's %f and %a. printf gained %a in the same batch, so without
     this the library could PRINT a double exactly and not read it back.

     Accumulated in binary rather than scaled in doubles: hex digits are exact
     powers of two, so the only rounding is the final one. Digits past the
     accumulator's room set a STICKY bit that is ORed into bit 0, which makes
     the (double) conversion's round-to-nearest-even land the same way glibc
     does on a tie — 0x1.00000000000008p+0 is 1.0 and ...18p+0 is the next
     double up, both verified against gcc. */
  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
    const char *hp = p + 2;
    unsigned long long hm = 0;
    int hexp = 0, hany = 0, sticky = 0;
    while (__crtl_hexval(*hp) >= 0) {
      int d = __crtl_hexval(*hp);
      if (hm <= 0x0FFFFFFFFFFFFFFFULL) hm = (hm << 4) | (unsigned long long)d;
      else { hexp += 4; if (d) sticky = 1; }
      hp++; hany = 1;
    }
    if (*hp == '.') {
      hp++;
      while (__crtl_hexval(*hp) >= 0) {
        int d = __crtl_hexval(*hp);
        if (hm <= 0x0FFFFFFFFFFFFFFFULL) { hm = (hm << 4) | (unsigned long long)d; hexp -= 4; }
        else if (d) sticky = 1;
        hp++; hany = 1;
      }
    }
    /* No hex digits at all is NOT a hex float: glibc consumes just the '0' and
       leaves "x...", which is what the caller's endptr must see. */
    if (hany) {
      if (*hp == 'p' || *hp == 'P') {
        const char *ep = hp + 1;
        int esign = 1, e = 0;
        if (*ep == '-') { esign = -1; ep++; } else if (*ep == '+') ep++;
        if (*ep >= '0' && *ep <= '9') {          /* an incomplete 'p' is not consumed */
          while (*ep >= '0' && *ep <= '9') { if (e < 100000) e = e * 10 + (*ep - '0'); ep++; }
          hexp += esign * e;
          hp = ep;
        }
      }
      if (sticky) hm |= 1ULL;
      if (end) *end = (char *)hp;
      return sign * __crtl_ldexp_ull(hm, hexp);
    }
    /* fall through: "0x" with no digits parses as the decimal 0 */
  }

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

/* atof is strtod with the error reporting thrown away — C says exactly that,
   so it is not an approximation. strtod here is already correctly rounded. */
double atof(const char *s) { return strtod(s, 0); }

/* bsearch: same comparator convention as qsort above (key first, then element),
   NULL when absent. The loop is written with a half-open [lo,hi) window so the
   midpoint cannot overflow and an empty range needs no special case. */
void *bsearch(const void *key, const void *base, size_t nmemb, size_t size,
              int (*cmp)(const void *, const void *)) {
  size_t lo = 0, hi = nmemb;
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    const char *p = (const char *)base + mid * size;
    int c = cmp(key, p);
    if (c == 0) return (void *)p;
    if (c < 0) hi = mid; else lo = mid + 1;
  }
  return 0;
}

/* rand/srand.

   The SEQUENCE is not portable and C does not fix it — this is the standard's
   own example generator (C99 7.20.2.2), not glibc's. So a test must not diff
   the numbers against a gcc build; it can only assert the properties C actually
   promises: deterministic for a given seed, in [0, RAND_MAX], and srand(1) is
   the default state. test/crand_props.c does exactly that, and says why.

   Chosen deliberately over copying glibc's TYPE_3 additive-feedback generator:
   matching a sequence nobody is entitled to rely on would buy a nicer diff and
   an obligation to keep it. */
static unsigned long __crtl_rand_state = 1;

void srand(unsigned int seed) { __crtl_rand_state = seed; }

int rand(void) {
  __crtl_rand_state = __crtl_rand_state * 1103515245UL + 12345UL;
  return (int)((__crtl_rand_state / 65536UL) % 32768UL);
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

/* time() deliberately does NOT live here — it belongs to <time.h>/time.c, which
   has the real PAL-backed clock (__crtl_time). A seed-only stub `time()` used to
   sit here for lua, and it was a silent-wrong-value trap: time.h does
   `#define time(t) __crtl_time(t)`, so in any TU that saw <time.h> first this
   definition expanded to a SECOND body for __crtl_time — one that always returns
   0 — and whichever module was pulled last won. Found by the C duplicate-
   definition warning (bug-c-string-h-compiles-stdlib-c-twice). */

/* long double == double in pxx: strtold forwards to strtod. */
double strtold(const char *s, char **end) { return strtod(s, end); }

/* ---- gcc bit-scan builtins (see stdlib.h; cfront renames __builtin_*) ----- */

int __pxx_builtin_clz32(unsigned int x) {
  int n = 0;
  while (!(x & 0x80000000u)) { x <<= 1; n++; }
  return n;
}

int __pxx_builtin_clz64(unsigned long long x) {
  int n = 0;
  while (!(x & 0x8000000000000000ull)) { x <<= 1; n++; }
  return n;
}

int __pxx_builtin_ctz32(unsigned int x) {
  int n = 0;
  while (!(x & 1u)) { x >>= 1; n++; }
  return n;
}

int __pxx_builtin_ctz64(unsigned long long x) {
  int n = 0;
  while (!(x & 1ull)) { x >>= 1; n++; }
  return n;
}

int __pxx_builtin_popcount32(unsigned int x) {
  int n = 0;
  while (x) { n += (int)(x & 1u); x >>= 1; }
  return n;
}

int __pxx_builtin_popcount64(unsigned long long x) {
  int n = 0;
  while (x) { n += (int)(x & 1ull); x >>= 1; }
  return n;
}

long long llabs(long long n)
{
    return n < 0 ? -n : n;
}

/* C99 7.20.6.2: quotient truncates toward zero, remainder has the numerator's
   sign, and quot*den + rem == num. `/` and `%` already satisfy that on this
   target, so these compute the pair rather than re-deriving the rule. */
div_t div(int num, int den)
{
    div_t r;
    r.quot = num / den;
    r.rem  = num % den;
    return r;
}

ldiv_t ldiv(long num, long den)
{
    ldiv_t r;
    r.quot = num / den;
    r.rem  = num % den;
    return r;
}

lldiv_t lldiv(long long num, long long den)
{
    lldiv_t r;
    r.quot = num / den;
    r.rem  = num % den;
    return r;
}

/* ---- strdup / strndup -----------------------------------------------------
 * Here rather than in string.c because they allocate, and malloc lives in this
 * file. Both return NULL on allocation failure, which callers do check.
 */
char *strdup(const char *s) {
  size_t n;
  char *p;
  if (!s) return 0;
  n = strlen(s);
  p = (char *)malloc(n + 1);
  if (!p) return 0;
  memcpy(p, s, n + 1);
  return p;
}

/* strndup: at most n bytes, and ALWAYS NUL-terminated even when the source is
 * longer — that termination is the difference from a bare malloc+memcpy and is
 * why callers reach for it on fixed-width fields. */
char *strndup(const char *s, size_t n) {
  size_t len = 0;
  char *p;
  if (!s) return 0;
  while (len < n && s[len]) len++;
  p = (char *)malloc(len + 1);
  if (!p) return 0;
  memcpy(p, s, len);
  p[len] = 0;
  return p;
}

/* ---- setenv / unsetenv ----------------------------------------------------
 * These mutate the same pxx_env_buf that getenv() reads, so a C program sees
 * its own writes.
 *
 * A STANDING CONSTRAINT, not an oversight: this buffer is NOT the one the
 * Pascal RTL's spawn path hands to execve (that is sysutils' EnvVars, see
 * decide-env-write-side option 3). Today that cannot diverge, because crtl
 * exposes no spawn surface at all — no execve, fork, system or posix_spawn in
 * any crtl header — so "setenv then exec" is unreachable from C. WHOEVER ADDS
 * A SPAWN SURFACE TO CRTL must make it pass this buffer, or unify the two
 * first; otherwise a C setenv silently fails to reach the child, which is
 * exactly the divergence that decision exists to prevent.
 *
 * Records are appended to the buffer rather than edited in place: an overwrite
 * of a longer value would need to shift everything after it, and the buffer is
 * a fixed 16K. An overwritten record is blanked by setting its first byte to
 * NUL... which getenv's scan would then treat as an empty record and skip, so
 * instead the name is mangled to a byte no environment name can contain. That
 * keeps the scan's structure (NUL-separated records) intact.
 */
static int pxx_env_put(const char *name, const char *value) {
  size_t nl = strlen(name), vl = strlen(value);
  long need = (long)nl + 1 + (long)vl + 1;
  if (pxx_env_len + need > PXX_ENV_BUFSZ) return -1;
  memcpy(&pxx_env_buf[pxx_env_len], name, nl);
  pxx_env_buf[pxx_env_len + (long)nl] = '=';
  memcpy(&pxx_env_buf[pxx_env_len + (long)nl + 1], value, vl);
  pxx_env_buf[pxx_env_len + need - 1] = 0;
  pxx_env_len += need;
  return 0;
}

/* Hide every existing record for `name` by making its NAME unmatchable. '\1'
 * cannot appear in a real environment name, and keeping the record's length
 * and terminator preserves the scan. */
static void pxx_env_hide(const char *name) {
  long i = 0;
  size_t j;
  while (i < pxx_env_len) {
    for (j = 0; name[j] && pxx_env_buf[i + (long)j] == name[j]; j++) ;
    if (!name[j] && pxx_env_buf[i + (long)j] == '=')
      pxx_env_buf[i] = 1;                 /* unmatchable first byte */
    while (i < pxx_env_len && pxx_env_buf[i]) i++;
    i++;
  }
}

int setenv(const char *name, const char *value, int overwrite) {
  if (!name || !*name || strchr(name, '=')) return -1;
  if (!value) value = "";
  pxx_env_load();
  if (getenv(name)) {
    if (!overwrite) return 0;             /* present and told not to replace */
    pxx_env_hide(name);
  }
  return pxx_env_put(name, value);
}

int unsetenv(const char *name) {
  if (!name || !*name || strchr(name, '=')) return -1;
  pxx_env_load();
  pxx_env_hide(name);
  return 0;
}
