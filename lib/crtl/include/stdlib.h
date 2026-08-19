/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_STDLIB_H
#define PXX_CRTL_STDLIB_H 1

#include <stddef.h>

#ifndef NULL
#define NULL 0
#endif

void *malloc(size_t size);
void *calloc(size_t count, size_t size);
void *realloc(void *ptr, size_t size);
void *reallocarray(void *ptr, size_t nmemb, size_t size);
void free(void *ptr);

int atoi(const char *s);
long atol(const char *s);
long long atoll(const char *s);
double atof(const char *s);
double strtod(const char *s, char **end);
/* long double == double in pxx: strtold aliases strtod. */
double strtold(const char *s, char **end);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);
long long strtoll(const char *s, char **end, int base);
unsigned long long strtoull(const char *s, char **end, int base);

int abs(int n);
long labs(long n);
long long llabs(long long n);

/* C89 div/ldiv, C99 lldiv. The quotient truncates TOWARD ZERO and the
   remainder takes the sign of the numerator, which is what `/` and `%` already
   do here -- the point of these is that the pair is computed together and the
   struct is what a caller destructures. */
typedef struct { int quot; int rem; } div_t;
typedef struct { long quot; long rem; } ldiv_t;
typedef struct { long long quot; long long rem; } lldiv_t;

div_t div(int num, int den);
ldiv_t ldiv(long num, long den);
lldiv_t lldiv(long long num, long long den);

/* the standard's minimum, and what our generator actually produces */
#ifndef RAND_MAX
#define RAND_MAX 32767
#endif

int rand(void);
void srand(unsigned int seed);

char *getenv(const char *name);

/* Environment write side. These mutate the SAME buffer getenv() reads, so a C
   program sees its own writes. NOTE they do not reach the Pascal RTL's spawn
   path (a separate buffer) — safe today only because crtl exposes no spawn
   surface at all; see the standing constraint at the definition in stdlib.c. */
int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);

/* Allocating string duplicates. strndup always NUL-terminates, even when the
   source is longer than n — that is the point of it. */
char *strdup(const char *s);
char *strndup(const char *s, size_t n);
char *realpath(const char *path, char *resolved);
int system(const char *command);

void qsort(void *base, size_t nmemb, size_t size, int (*cmp)(const void *, const void *));
void *bsearch(const void *key, void *base, size_t nmemb, size_t size, int (*cmp)(const void *, const void *));

void abort(void);
void exit(int status);
void _Exit(int status);
int atexit(void (*func)(void));

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

#define MB_CUR_MAX 1

/* gcc bit-scan builtins, renamed by the C frontend (__builtin_clz ->
 * __pxx_builtin_clz32, ...): cfront has no intrinsic lowering for them yet, so
 * they resolve to these plain-C loops via the normal crtl auto-pull.
 *
 * clz/ctz/popcount are undefined for a zero argument, exactly like the gcc
 * builtins. ffs and parity are NOT -- gcc defines both at zero (0 and 0), so
 * they are written to answer it rather than routed through ctz/popcount. */
int __pxx_builtin_clz32(unsigned int x);
int __pxx_builtin_clz64(unsigned long long x);
int __pxx_builtin_ctz32(unsigned int x);
int __pxx_builtin_ctz64(unsigned long long x);
int __pxx_builtin_popcount32(unsigned int x);
int __pxx_builtin_popcount64(unsigned long long x);
int __pxx_builtin_ffs32(unsigned int x);
int __pxx_builtin_ffs64(unsigned long long x);
int __pxx_builtin_parity32(unsigned int x);
int __pxx_builtin_parity64(unsigned long long x);
unsigned short __pxx_builtin_bswap16(unsigned short x);
unsigned int __pxx_builtin_bswap32(unsigned int x);
unsigned long long __pxx_builtin_bswap64(unsigned long long x);

#endif
