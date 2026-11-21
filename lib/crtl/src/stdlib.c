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
#include <fcntl.h>
#include <inttypes.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/ioctl.h>

extern void *__pxx_malloc(long n);
extern void  __pxx_free(void *p);
extern void *__pxx_realloc(void *p, long n);
extern long  __pxx_malloc_usable_size(void *p);
extern void  __pxx_exit(int code);
extern int   __pxx_atexit(void (*func)(void));
extern void  __pxx_atexit_run(void);

/* ---- heap ----------------------------------------------------------------- */

/* Aligned blocks. The pool aligns to 8 and nothing more, so posix_memalign &
   co. over-allocate and hand out an aligned address inside the block. The two
   words below that address say so: [a-16] is the pool block, [a-8] is
   PXX_ALIGNED_TAG. A pool block's own word at [p-8] is its size, a multiple of
   8 (on i386 its low half is), and the tag is odd, so the two never meet. */
#define PXX_ALIGNED_TAG 0x5A11A11EDA11A11FULL
static int pxx_is_aligned_blk(void *p) {
  return p && *(unsigned long long *)((char *)p - 8) == PXX_ALIGNED_TAG;
}
static void *pxx_aligned_base(void *p) { return *(void **)((char *)p - 16); }

static void *pxx_alloc_aligned(size_t align, size_t size) {
  char *raw;
  size_t a;
  if (align <= 8) return __pxx_malloc((long)size);
  if (size > (size_t)-1 - align - 16) return 0;
  raw = (char *)__pxx_malloc((long)(size + align + 16));
  if (!raw) return 0;
  a = ((size_t)raw + 16 + align - 1) & ~(align - 1);
  *(void **)(a - 16) = raw;
  *(unsigned long long *)(a - 8) = PXX_ALIGNED_TAG;
  return (void *)a;
}

void *malloc(size_t size) { return __pxx_malloc((long)size); }
void  free(void *ptr) {
  if (pxx_is_aligned_blk(ptr)) {
    void *raw = pxx_aligned_base(ptr);
    *(unsigned long long *)((char *)ptr - 8) = 0;   /* a stale tag must not outlive it */
    __pxx_free(raw);
    return;
  }
  __pxx_free(ptr);
}

/* Reads the block's own header through the bridge -- see malloc.h for why this
   is the rounded-up TRUE size and not the requested one. NULL and an
   implausible header both answer 0. */
size_t malloc_usable_size(void *ptr) {
  if (pxx_is_aligned_blk(ptr)) {
    char *raw = (char *)pxx_aligned_base(ptr);
    return (size_t)__pxx_malloc_usable_size(raw) - (size_t)((char *)ptr - raw);
  }
  return (size_t)__pxx_malloc_usable_size(ptr);
}

/* An aligned block moves to an ordinary one, as glibc's realloc does. */
void *realloc(void *ptr, size_t size) {
  if (pxx_is_aligned_blk(ptr)) {
    size_t have = malloc_usable_size(ptr);
    void *n = __pxx_malloc((long)size);
    if (!n) return 0;
    memcpy(n, ptr, have < size ? have : size);
    free(ptr);
    return n;
  }
  return __pxx_realloc(ptr, (long)size);
}

int posix_memalign(void **out, size_t align, size_t size) {
  void *p;
  if (align < sizeof(void *) || (align & (align - 1))) return EINVAL;
  p = pxx_alloc_aligned(align, size);
  if (!p) return ENOMEM;
  *out = p;
  return 0;
}

void *aligned_alloc(size_t align, size_t size) {
  if (align == 0 || (align & (align - 1))) { errno = EINVAL; return 0; }
  return pxx_alloc_aligned(align, size);
}

void *memalign(size_t align, size_t size) {
  if (align == 0 || (align & (align - 1))) { errno = EINVAL; return 0; }
  return pxx_alloc_aligned(align, size);
}

void *valloc(size_t size) { return pxx_alloc_aligned(4096, size); }

void *calloc(size_t count, size_t size) {
  /* PXXAlloc already zeroes; just guard the multiply overflow. */
  size_t total = count * size;
  if (size != 0 && total / size != count) return 0;   /* overflow */
  return __pxx_malloc((long)total);
}

void *reallocarray(void *ptr, size_t nmemb, size_t size) {
  size_t total = nmemb * size;
  if (size != 0 && total / size != nmemb) return 0;
  return realloc(ptr, total);
}

/* ---- process control ------------------------------------------------------ */

/* The handler list itself lives in lib/rtl/pxxcio.pas — see the note there. In
   short: a `return` from main exits through the compiler's entry stub, whose
   only hook is the unit-finalization runner, so a list on this side would be
   drained by exit() and silently skipped on the path most C programs take. */
int atexit(void (*func)(void)) { return __pxx_atexit(func); }

/* exit() runs the handlers; _Exit and abort deliberately do not (C99 7.20.4.4
   and 7.20.4.1 — _Exit's whole purpose is to skip them, and abort is an
   abnormal termination). The drain pops, so exit() from inside a handler
   continues with the rest and never repeats one. */
void exit(int code)  { __pxx_atexit_run(); __pxx_exit(code); }
void _Exit(int code) { __pxx_exit(code); }
void abort(void)     { __pxx_exit(134); }   /* 128 + SIGABRT(6) */

/* ---- temporary files ------------------------------------------------------ */

extern int __pxx_open(const char *path, int flags, int mode);
extern int __pxx_close(int fd);
extern int __pxx_remove(const char *path);
extern int __pxx_getpid(void);
extern int __pxx_realtime(void *secOut, void *usecOut);

/* mkstemp(3). The template's trailing XXXXXX is replaced and the file created
   with O_EXCL, so the name is claimed by the CREATE, not by the guess — which
   is the whole security property, and it holds however weak the guess is. We
   retry on EEXIST like glibc does.

   The digits come from the clock, the pid and the attempt counter. That is NOT
   a CSPRNG and is not claimed to be one: it makes collisions unlikely, and
   O_EXCL makes them harmless when they happen. Mode is 0600, per POSIX. */
static int pxx_mktemp_open(char *tmpl, int flags, int mode)
{
  static const char tab[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  size_t len = strlen(tmpl);
  char *x;
  long long sec = 0, usec = 0;
  unsigned long long v;
  int attempt, i, fd;

  if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX") != 0) { errno = EINVAL; return -1; }
  x = tmpl + len - 6;

  __pxx_realtime(&sec, &usec);
  v = (unsigned long long)sec * 1000000ULL + (unsigned long long)usec;
  v ^= (unsigned long long)__pxx_getpid() << 20;

  for (attempt = 0; attempt < 4096; attempt++) {
    unsigned long long r = v + (unsigned long long)attempt * 7777ULL;
    for (i = 0; i < 6; i++) { x[i] = tab[r % 62]; r /= 62; r += 0x9E3779B97F4A7C15ULL; }
    fd = __pxx_open(tmpl, flags, mode);
    if (fd >= 0) return fd;
    if (fd != -EEXIST) { errno = -fd; return -1; }
  }
  errno = EEXIST;
  return -1;
}

int mkstemp(char *tmpl)
{
  return pxx_mktemp_open(tmpl, O_RDWR | O_CREAT | O_EXCL, 0600);
}

/* mktemp(3), the DEPRECATED one, and the deprecation is the point: it returns
   a name it did not claim, so anything may create that path before the caller
   does. It exists because real code asks for a name without wanting the file --
   busybox's `mktemp -u' is exactly that -- and refusing to provide it would
   only push callers onto something worse.

   Implemented ON TOP of the same claim-by-O_EXCL search, then the file is
   unlinked: that is how the name is known to have been available, and it is
   strictly better than testing with access(2), which answers about a moment
   that has already passed. The race is still there and is inherent to the
   interface, not to this implementation.

   Returns tmpl on success. On failure it returns tmpl with the template
   EMPTIED to "" -- glibc's convention, and the reason a caller must test the
   first byte rather than the pointer. */
char *mktemp(char *tmpl)
{
  int fd = pxx_mktemp_open(tmpl, O_RDWR | O_CREAT | O_EXCL, 0600);
  if (fd < 0) { tmpl[0] = '\0'; return tmpl; }
  __pxx_close(fd);
  __pxx_remove(tmpl);
  return tmpl;
}

/* mkostemp adds caller flags (O_CLOEXEC / O_APPEND); the access mode and the
   O_CREAT|O_EXCL pair are ours and are not negotiable. */
int mkostemp(char *tmpl, int flags)
{
  return pxx_mktemp_open(tmpl, O_RDWR | O_CREAT | O_EXCL | flags, 0600);
}

/* mkdtemp(3): the same name search, claimed with mkdir instead of open. */
extern int __pxx_mkdir(const char *path, int mode);

char *mkdtemp(char *tmpl)
{
  static const char tab[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  size_t len = strlen(tmpl);
  char *x;
  long long sec = 0, usec = 0;
  unsigned long long v;
  int attempt, i, rc;

  if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX") != 0) { errno = EINVAL; return 0; }
  x = tmpl + len - 6;

  __pxx_realtime(&sec, &usec);
  v = (unsigned long long)sec * 1000000ULL + (unsigned long long)usec;
  v ^= (unsigned long long)__pxx_getpid() << 20;

  for (attempt = 0; attempt < 4096; attempt++) {
    unsigned long long r = v + (unsigned long long)attempt * 7777ULL;
    for (i = 0; i < 6; i++) { x[i] = tab[r % 62]; r /= 62; r += 0x9E3779B97F4A7C15ULL; }
    rc = __pxx_mkdir(tmpl, 0700);
    if (rc == 0) return tmpl;
    if (rc != -EEXIST) { errno = -rc; return 0; }
  }
  errno = EEXIST;
  return 0;
}

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
extern int __pxx_remove(const char *path);

#define PXX_ENV_BUFSZ 16384

static char pxx_env_buf[PXX_ENV_BUFSZ];
static long pxx_env_len = 0;
static int pxx_env_loaded = 0;
/* What did NOT fit: the startup environment from record pxx_env_nloaded on.
   Only set when the load truncated; pxx_env_publish passes these on to a
   child unchanged, so a write never shrinks a large environment. */
static char **pxx_env_startup = 0;
static long pxx_env_nloaded = 0;
static int pxx_env_truncated = 0;

/* AND THE FALLBACK, ADDED 2026-09-19 BECAUSE /proc IS A LINUX DETAIL AND NOT
   THE ENVIRONMENT. Measured on wasm32 the day hosted C first ran there: the
   entry stub fills `environ` correctly from WASI's environ_sizes_get/
   environ_get -- a probe that walks `environ` directly prints every variable
   wasmtime was given -- and getenv() answered (null) for all of them, because
   it was reading a procfs file a WASI module has no filesystem for. Two
   environments in one program that never spoke to each other, and the one the
   C standard names was the one nobody read.

   ORDER IS /proc FIRST AND `environ` SECOND, which is the weaker of the two
   correct designs and is chosen on purpose. glibc's getenv reads `environ` and
   nothing else, so preferring it here would be closer to the standard -- but
   `environ` is filled by __pxx_run_initializers at the top of main, and a
   getenv() reached from a file-scope initializer would then see an empty
   environment on a target where /proc would have answered. That ordering
   property has NOT been measured, and this arm is strictly additive as
   written: every target with a readable /proc/self/environ behaves exactly as
   it did before, byte for byte. Retire the caveat by measuring when `environ`
   becomes non-null relative to the first getenv on each hosted target; if it
   is always before, flip the order and delete the /proc read.

   The copy is bounded by the same buffer the /proc path fills and stops on the
   first record that would not fit, so an over-large environment truncates
   rather than overruns -- the same "behave like a program started without it"
   stance the header above takes for a failed open. */
extern char **environ;

static void pxx_env_load(void) {
  int fd;
  long got;
  char **e;
  const char *r;
  long n;
  if (pxx_env_loaded) return;
  pxx_env_loaded = 1;
  fd = __pxx_open("/proc/self/environ", 0, 0);   /* O_RDONLY */
  pxx_env_startup = environ;
  if (fd >= 0) {
    got = __pxx_read(fd, pxx_env_buf, PXX_ENV_BUFSZ);
    __pxx_close(fd);
    if (got > 0) {
      if (got >= PXX_ENV_BUFSZ) {
        /* full: the last record may be cut; keep whole ones only */
        while (got > 0 && pxx_env_buf[got - 1]) got--;
        pxx_env_truncated = 1;
      }
      pxx_env_len = got;
      for (n = 0; n < got; n++) if (!pxx_env_buf[n]) pxx_env_nloaded++;
      return;
    }
  }
  e = environ;
  if (!e) return;
  while (*e) {
    r = *e;
    n = 0;
    while (r[n]) n++;
    if (pxx_env_len + n + 1 > PXX_ENV_BUFSZ) { pxx_env_truncated = 1; break; }
    for (got = 0; got <= n; got++) pxx_env_buf[pxx_env_len + got] = r[got];
    pxx_env_len += n + 1;
    pxx_env_nloaded++;
    e++;
  }
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

/* realpath: an absolute path with every symlink, `.` and `..` resolved, each
   component checked to exist. It used to be an identity copy, so `./x.h` and
   `../d/x.h` never compared equal and tcc's `#pragma once` included one header
   three times (tests2/18). Errors are glibc's: ENOENT for a missing component
   or a dangling link, ENOTDIR for a non-directory followed by more path (a
   trailing slash included), ELOOP after 40 links (glibc's MAXSYMLINKS),
   ENAMETOOLONG past PATH_MAX, EINVAL for NULL. `..` of a symlinked directory
   is taken in the TARGET, as in the kernel, because the link is resolved
   before the `..` is seen. */
char *realpath(const char *path, char *resolved) {
  char out[PATH_MAX], rest[PATH_MAX], link[PATH_MAX];
  size_t ol, rl, cl, tl, i;
  int links = 0;
  struct stat st;
  const char *comp;
  if (!path) { errno = EINVAL; return 0; }
  if (!*path) { errno = ENOENT; return 0; }
  rl = strlen(path);
  if (rl >= PATH_MAX) { errno = ENAMETOOLONG; return 0; }
  memcpy(rest, path, rl + 1);
  if (rest[0] == '/') { out[0] = '/'; out[1] = 0; }
  else if (!getcwd(out, sizeof out)) return 0;
  ol = strlen(out);
  i = 0;
  for (;;) {
    while (rest[i] == '/') i++;
    if (!rest[i]) break;
    comp = rest + i;
    cl = 0;
    while (comp[cl] && comp[cl] != '/') cl++;
    i += cl;
    if (cl == 1 && comp[0] == '.') continue;
    if (cl == 2 && comp[0] == '.' && comp[1] == '.') {
      while (ol > 1 && out[ol - 1] != '/') ol--;
      if (ol > 1) ol--;
      out[ol] = 0;
      continue;
    }
    if (ol + (ol > 1) + cl >= PATH_MAX) { errno = ENAMETOOLONG; return 0; }
    if (ol > 1) out[ol++] = '/';
    memcpy(out + ol, comp, cl);
    ol += cl;
    out[ol] = 0;
    if (lstat(out, &st) != 0) return 0;
    if (S_ISLNK(st.st_mode)) {
      ssize_t n;
      if (++links > 40) { errno = ELOOP; return 0; }
      n = readlink(out, link, sizeof link - 1);
      if (n < 0) return 0;
      tl = (size_t)n;
      /* new rest = link target + what was left of the old one */
      rl = strlen(rest + i);
      if (tl + rl + 1 >= PATH_MAX) { errno = ENAMETOOLONG; return 0; }
      memmove(rest + tl, rest + i, rl + 1);
      memcpy(rest, link, tl);
      i = 0;
      /* drop the link's own name; an absolute target restarts at the root */
      ol -= cl;
      if (ol > 1) ol--;
      out[ol] = 0;
      if (rest[0] == '/') { out[0] = '/'; out[1] = 0; ol = 1; }
      continue;
    }
    if (!S_ISDIR(st.st_mode) && rest[i]) { errno = ENOTDIR; return 0; }
  }
  if (!resolved) {
    resolved = (char *)malloc(ol + 1);
    if (!resolved) { errno = ENOMEM; return 0; }
  }
  memcpy(resolved, out, ol + 1);
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

  /* INF, INFINITY and NAN, any case, NAN optionally followed by (n-char-seq)
     (C11 7.22.1.3). Missing, so strtod("inf") was 0 consuming nothing, and
     toybox `sort -g' ordered NaN/-inf/+infinity as zeros. The NaN is built
     from its bits: 0.0/0.0 on x86 is the default NaN, sign bit SET, and
     glibc's strtod("nan") is positive (strtod("-nan") negative). */
  {
    static const char inf_s[] = "infinity";
    int i = 0;
    while (i < 8 && (p[i] | 0x20) == inf_s[i]) i++;
    if (i >= 3) {              /* "infinit" is "inf" and 4 left over */
      if (end) *end = (char *)(p + (i == 8 ? 8 : 3));
      return sign * (1.0 / 0.0);
    }
    if ((p[0] | 0x20) == 'n' && (p[1] | 0x20) == 'a' && (p[2] | 0x20) == 'n') {
      union { unsigned long long u; double d; } nb;
      const char *q = p + 3;
      if (*q == '(') {
        const char *r = q + 1;
        while ((*r >= '0' && *r <= '9') || ((*r | 0x20) >= 'a' && (*r | 0x20) <= 'z') || *r == '_') r++;
        if (*r == ')') q = r + 1;
      }
      nb.u = 0x7FF8000000000000ULL;
      if (sign < 0) nb.u |= 0x8000000000000000ULL;
      if (end) *end = (char *)q;
      return nb.d;
    }
  }

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
    /* a finite input that overflowed: C11 7.22.1.3 wants ERANGE with the
       HUGE_VAL it already is. (Underflow's ERANGE is not set here.) */
    if (v - v != 0) errno = ERANGE;
  }
  if (end) *end = (char *)(any ? p : s);
  return sign * v;
}

/* system(): `/bin/sh -c command', waited for, returning the raw wait status.
 *
 * THIS REVERSES A POSITION AND THE OLD ONE IS WORTH KEEPING IN VIEW. It used to
 * read "the libc-free runtime has no command processor", answer 0 to
 * system(NULL) and -1 to everything else. That was true when written; it is not
 * now. crtl has fork, execvp, pipe, dup2 and waitpid, so the machinery is here
 * and the only remaining question is whether the TARGET has a /bin/sh. Where it
 * does not, execvp fails, the child exits 127, and the caller sees the same 127
 * glibc would give it -- a real answer about a real system, where -1 for every
 * command was a claim about this runtime that callers could not act on.
 *
 * system(NULL) still asks whether a command processor is available, and the
 * honest answer needs a LOOK rather than a constant: it reports 1 only if
 * /bin/sh is executable. Returning 1 unconditionally would be the same kind of
 * unfounded claim in the other direction.
 *
 * EINTR is not failure in the wait: a signal must not lose the child's status,
 * which is the entire return value. */
int system(const char *command) {
  int pid, status = 0;

  if (command == 0) return access("/bin/sh", X_OK) == 0 ? 1 : 0;

#if defined(__PXX_VFORK_STUB__)   /* the compiler writes vfork (xtensa Linux); bug-c-s3-idf-c-programs-fail-to-link-vfork */
  pid = vfork();   /* no-MMU Nilix has no fork; the child only execs or exits */
#else
  pid = fork();
#endif
  if (pid < 0) return -1;
  if (pid == 0) {
    char *argv[4];
    argv[0] = (char *)"sh";
    argv[1] = (char *)"-c";
    argv[2] = (char *)command;
    argv[3] = 0;
    execvp("/bin/sh", argv);
    _exit(127);
  }
  while (waitpid(pid, &status, 0) < 0)
    if (errno != EINTR) return -1;
  return status;
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
static unsigned long long __crtl_rand_state = 1;

void srand(unsigned int seed) { __crtl_rand_state = seed; }

/* ---- rand48 (see stdlib.h). glibc starts the global X at ZERO when nothing
   seeded it, and so does this. ---- */
static unsigned short __crtl_r48_x[3] = { 0, 0, 0 };
static unsigned long long __crtl_r48_a = 0x5DEECE66DULL;
static unsigned short __crtl_r48_c = 0xB;
static unsigned short __crtl_r48_old[3];

/* Advance xsubi one step and return the new 48-bit value. */
static unsigned long long __crtl_r48_step(unsigned short *xs) {
  unsigned long long x = (unsigned long long)xs[0] |
                         ((unsigned long long)xs[1] << 16) |
                         ((unsigned long long)xs[2] << 32);
  x = (x * __crtl_r48_a + __crtl_r48_c) & 0xFFFFFFFFFFFFULL;
  xs[0] = (unsigned short)(x & 0xFFFF);
  xs[1] = (unsigned short)((x >> 16) & 0xFFFF);
  xs[2] = (unsigned short)((x >> 32) & 0xFFFF);
  return x;
}

/* X * 2^-48 is exact in a double (48 < 53 bits), and it is what glibc's
   build-a-mantissa-in-[1,2)-then-subtract-1 produces. */
double erand48(unsigned short xsubi[3]) {
  return (double)__crtl_r48_step(xsubi) * (1.0 / 281474976710656.0);
}
double drand48(void) { return erand48(__crtl_r48_x); }

long nrand48(unsigned short xsubi[3]) {
  return (long)(__crtl_r48_step(xsubi) >> 17);
}
long lrand48(void) { return nrand48(__crtl_r48_x); }

/* The top 32 bits as a SIGNED 32-bit value, sign-extended to long. */
long jrand48(unsigned short xsubi[3]) {
  return (long)(int)(unsigned int)(__crtl_r48_step(xsubi) >> 16);
}
long mrand48(void) { return jrand48(__crtl_r48_x); }

void srand48(long seedval) {
  __crtl_r48_x[0] = 0x330E;
  __crtl_r48_x[1] = (unsigned short)(seedval & 0xFFFF);
  __crtl_r48_x[2] = (unsigned short)((seedval >> 16) & 0xFFFF);
  __crtl_r48_a = 0x5DEECE66DULL;
  __crtl_r48_c = 0xB;
}

/* Returns the PREVIOUS X in a static buffer, as POSIX says. */
unsigned short *seed48(unsigned short seed16v[3]) {
  int i;
  for (i = 0; i < 3; i++) __crtl_r48_old[i] = __crtl_r48_x[i];
  for (i = 0; i < 3; i++) __crtl_r48_x[i] = seed16v[i];
  __crtl_r48_a = 0x5DEECE66DULL;
  __crtl_r48_c = 0xB;
  return __crtl_r48_old;
}

void lcong48(unsigned short param[7]) {
  int i;
  for (i = 0; i < 3; i++) __crtl_r48_x[i] = param[i];
  __crtl_r48_a = (unsigned long long)param[3] |
                 ((unsigned long long)param[4] << 16) |
                 ((unsigned long long)param[5] << 32);
  __crtl_r48_c = param[6];
}

/* THE RANGE IS 31 BITS, and that is a compatibility fact rather than a taste.
   RAND_MAX was 32767 -- C99's required MINIMUM, and legal -- but real code
   selects an implementation on it and simply refuses the small one:
   busybox's editors/awk.c is `#if RAND_MAX >= 0x7fffffff ... #else #error Not
   implemented for this value of RAND_MAX'. So awk did not compile, and the
   diagnostic was about the macro rather than about anything missing. glibc,
   musl and the BSDs all use 0x7fffffff; being the one runtime that does not is
   a gap dressed as a conforming choice.

   The MACRO AND THE GENERATOR HAVE TO AGREE -- raising RAND_MAX over a
   generator that still returns 15 bits would leave every high bit permanently
   zero, which is the plausible-wrong-value shape and would pass an in-range
   test. So the state widened to 64 bits and the result is taken from the HIGH
   half: the low bits of a power-of-two LCG have famously short periods (bit 0
   alternates), and that is exactly the half the old `/65536' was already
   avoiding, for the same reason.

   The SEQUENCE is still not glibc's and still must not be diffed against a gcc
   build -- C fixes none of it. test/cstdlib_batch3.c asserts only what the
   standard promises: deterministic for a seed, within [0, RAND_MAX], and
   srand(1) as the initial state. */
int rand(void) {
  __crtl_rand_state = __crtl_rand_state * 6364136223846793005ULL
                    + 1442695040888963407ULL;
  return (int)((__crtl_rand_state >> 33) & 0x7fffffffULL);
}

/* random/srandom share rand's generator and state, as glibc's do. */
long random(void) { return (long)rand(); }
void srandom(unsigned int seed) { srand(seed); }

/* rand_r: the caller owns the state, so there is nothing process-wide to race
   on. IT CANNOT SHARE rand()'s GENERATOR, AND THAT IS FORCED BY THE SIGNATURE
   RATHER THAN CHOSEN: POSIX types the seed as `unsigned int', so there are 32
   bits of state where rand() keeps 64 -- and rand()'s whole design, argued
   directly above, is to return the HIGH half because the low bits of a
   power-of-two LCG have famously short periods. With 32 bits there is no high
   half to take.

   So this is the classical three-round construction, which exists to solve
   exactly that constraint: three LCG steps, each contributing its upper bits,
   assembled into 31. The range therefore still matches RAND_MAX (0x7fffffff),
   which is the one property a caller is entitled to rely on.

   THE TWO SEQUENCES DIFFER AND THAT IS CONFORMING -- nothing requires rand_r
   to agree with rand. The caveat above applies unchanged: do not diff either
   against a gcc build. What may be asserted is what the standard promises --
   deterministic for a given seed, within [0, RAND_MAX], and the seed advanced
   so successive calls differ. */
int rand_r(unsigned int *seed) {
  unsigned int next;
  int result;

  if (!seed) return 0;
  next = *seed;

  next = next * 1103515245u + 12345u;
  result = (int)((next / 65536u) % 2048u);

  next = next * 1103515245u + 12345u;
  result <<= 10;
  result ^= (int)((next / 65536u) % 1024u);

  next = next * 1103515245u + 12345u;
  result <<= 10;
  result ^= (int)((next / 65536u) % 1024u);

  *seed = next;
  return result;
}

/* GNU qsort_r, the same insertion sort as qsort below with the caller's
   `arg' handed to every comparison. feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools */
void qsort_r(void *base, size_t nmemb, size_t size,
             int (*cmp)(const void *, const void *, void *), void *arg) {
  char *a = (char *)base;
  size_t i, j;
  for (i = 1; i < nmemb; i++) {
    for (j = i; j > 0; j--) {
      char *cur = a + j * size;
      char *prv = a + (j - 1) * size;
      if (cmp(prv, cur, arg) <= 0) break;
      __crtl_swap(prv, cur, size);
    }
  }
}

/* getloadavg: up to three numbers from /proc/loadavg; the count read, or -1.
   xload's only data source. */
extern int __pxx_close(int fd);
int getloadavg(double loadavg[], int nelem) {
  char buf[128], *p, *e;
  int fd, i;
  long long n;
  if (nelem < 0) { errno = EINVAL; return -1; }
  fd = __pxx_open("/proc/loadavg", O_RDONLY, 0);
  if (fd < 0) { errno = -fd; return -1; }
  n = __pxx_read(fd, buf, sizeof buf - 1);
  __pxx_close(fd);
  if (n <= 0) return -1;
  buf[n] = 0;
  p = buf;
  for (i = 0; i < nelem && i < 3; i++) {
    loadavg[i] = strtod(p, &e);
    if (e == p) break;
    p = e;
  }
  return i;
}

/* secure_getenv: NULL when the real and effective ids differ, which is
   glibc's AT_SECURE condition for every case a set-id binary produces. */
extern unsigned int getuid(void), geteuid(void), getgid(void), getegid(void);
char *secure_getenv(const char *name) {
  if (getuid() != geteuid() || getgid() != getegid()) return (char *)0;
  return getenv(name);
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

/* ZERO HANGS THESE FOUR WITHOUT THE GUARD. No shift of 0 ever reaches the bit
   the loop is waiting for, so the program spins forever -- it does not return a
   wrong answer, it never returns. A csmith program did exactly that: it compiled
   clean at every -O level and hung, while a gcc-built binary of the same source
   ran to completion (bug-c-clz-ctz-of-zero-spin-forever-in-crtl).

   ffs below already guards zero, under a comment noting that ffs is DEFINED at
   zero "unlike clz/ctz". The defined case was protected and the two UNDEFINED
   ones were left to spin -- which is backwards: undefined means we may return
   anything we like, and "anything" is much cheaper to supply than an infinite
   loop is to debug.

   WHY THE FULL WIDTH, and this argument does NOT come from the corpus: the
   program that found the hang prints the same checksum whether this returns 0,
   7 or 63, because the checksum cannot see the value -- so an oracle match here
   would be citing a constant. The value is chosen instead because x86 `lzcnt`
   and `tzcnt` answer with the operand width at zero, and gcc's own constant
   folder gave 64 for a literal `__builtin_clzll(0)`. C leaves it undefined, so
   this is a deliberate convention, not a conformance claim. */
int __pxx_builtin_clz32(unsigned int x) {
  int n = 0;
  if (x == 0u) return 32;
  while (!(x & 0x80000000u)) { x <<= 1; n++; }
  return n;
}

int __pxx_builtin_clz64(unsigned long long x) {
  int n = 0;
  if (x == 0ull) return 64;
  while (!(x & 0x8000000000000000ull)) { x <<= 1; n++; }
  return n;
}

int __pxx_builtin_ctz32(unsigned int x) {
  int n = 0;
  if (x == 0u) return 32;
  while (!(x & 1u)) { x >>= 1; n++; }
  return n;
}

int __pxx_builtin_ctz64(unsigned long long x) {
  int n = 0;
  if (x == 0ull) return 64;
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

/* ffs: 1 + index of the least significant set bit, 0 for a zero argument.
   Unlike clz/ctz, ffs is DEFINED at zero -- do not route it through ctz. */
int __pxx_builtin_ffs32(unsigned int x) {
  int n = 1;
  if (x == 0u) return 0;
  while (!(x & 1u)) { x >>= 1; n++; }
  return n;
}

int __pxx_builtin_ffs64(unsigned long long x) {
  int n = 1;
  if (x == 0ull) return 0;
  while (!(x & 1ull)) { x >>= 1; n++; }
  return n;
}

/* parity: number of set bits mod 2. Defined at zero (answers 0). */
int __pxx_builtin_parity32(unsigned int x) {
  int n = 0;
  while (x) { n ^= (int)(x & 1u); x >>= 1; }
  return n;
}

int __pxx_builtin_parity64(unsigned long long x) {
  int n = 0;
  while (x) { n ^= (int)(x & 1ull); x >>= 1; }
  return n;
}

/* bswap: reverse the byte order. Returns the same width it took. */
unsigned short __pxx_builtin_bswap16(unsigned short x) {
  return (unsigned short)(((x & 0x00FFu) << 8) | ((x & 0xFF00u) >> 8));
}

unsigned int __pxx_builtin_bswap32(unsigned int x) {
  return ((x & 0x000000FFu) << 24) | ((x & 0x0000FF00u) << 8) |
         ((x & 0x00FF0000u) >> 8)  | ((x & 0xFF000000u) >> 24);
}

unsigned long long __pxx_builtin_bswap64(unsigned long long x) {
  return ((x & 0x00000000000000FFull) << 56) | ((x & 0x000000000000FF00ull) << 40) |
         ((x & 0x0000000000FF0000ull) << 24) | ((x & 0x00000000FF000000ull) << 8)  |
         ((x & 0x000000FF00000000ull) >> 8)  | ((x & 0x0000FF0000000000ull) >> 24) |
         ((x & 0x00FF000000000000ull) >> 40) | ((x & 0xFF00000000000000ull) >> 56);
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
 * crtl's exec* family passes `environ`, so every write ends in
 * pxx_env_publish(), which points `environ` at this buffer's live records.
 * The comment here used to say crtl had no spawn surface and that whoever
 * added one must make it pass this buffer; exec* was added and that was
 * missed, so setenv never reached a child
 * (bug-crtl-setenv-and-putenv-did-not-reach-an-execd-child). This buffer is
 * still NOT the Pascal RTL's sysutils EnvVars (decide-env-write-side
 * option 3): a C setenv is not seen by a Pascal spawn in the same program.
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
/* Point `environ` at the buffer's live records, so a child started with
 * exec* gets what setenv/putenv/unsetenv/clearenv made. Before this, exec*
 * passed `environ` -- still the startup envp -- and every write was lost at
 * the exec: busybox udhcpc ran its script without interface/ip/router and
 * DHCP never configured an address (pixx-cc, 2026-11-15).
 * bug-crtl-setenv-and-putenv-did-not-reach-an-execd-child
 *
 * Called after every write. Hidden records (first byte 1) and empty ones are
 * left out; what the load could not fit is passed on from the startup
 * environment unchanged. The vector is malloc'd and replaced, never freed
 * while in use: a caller may hold the old `environ`. */
static char **pxx_env_vec = 0;
static long pxx_env_cap = 0;

static void pxx_env_publish(void) {
  long i, n = 0, k;
  char **v;
  for (i = 0; i < pxx_env_len; i++)
    if (!pxx_env_buf[i]) n++;
  if (pxx_env_truncated && pxx_env_startup) {
    for (k = 0; k < pxx_env_nloaded && pxx_env_startup[k]; k++) ;
    if (k == pxx_env_nloaded)
      for (; pxx_env_startup[k]; k++) n++;
  }
  if (n + 1 > pxx_env_cap) {
    v = (char **)malloc(sizeof(char *) * (size_t)(n + 16));
    if (!v) return;                      /* keep the old vector: stale beats none */
    pxx_env_vec = v;                     /* the old one leaks: someone may hold it */
    pxx_env_cap = n + 16;
  }
  v = pxx_env_vec;
  n = 0;
  i = 0;
  while (i < pxx_env_len) {
    if (pxx_env_buf[i] != 1 && pxx_env_buf[i] != 0) v[n++] = &pxx_env_buf[i];
    while (i < pxx_env_len && pxx_env_buf[i]) i++;
    i++;
  }
  if (pxx_env_truncated && pxx_env_startup) {
    for (k = 0; k < pxx_env_nloaded && pxx_env_startup[k]; k++) ;
    if (k == pxx_env_nloaded)
      for (; pxx_env_startup[k]; k++) v[n++] = pxx_env_startup[k];
  }
  v[n] = 0;
  environ = v;
}

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
  if (pxx_env_put(name, value) != 0) { pxx_env_publish(); return -1; }
  pxx_env_publish();
  return 0;
}

int unsetenv(const char *name) {
  if (!name || !*name || strchr(name, '=')) return -1;
  pxx_env_load();
  pxx_env_hide(name);
  pxx_env_publish();
  return 0;
}

/* putenv(): add or replace a record given as one "NAME=VALUE" string.
 * busybox's env applet uses it beside setenv.
 *
 * A DELIBERATE DIVERGENCE FROM GLIBC, stated rather than hidden: POSIX lets
 * putenv() make the CALLER'S BUFFER part of the environment, so under glibc a
 * later write through that same pointer changes the variable. This copies into
 * pxx_env_buf like setenv does, because the buffer here is a fixed 16K arena
 * that getenv() returns interior pointers into -- there is nowhere to store a
 * foreign pointer without giving every record a discriminator and teaching
 * every scan about it. A program that writes through the pointer afterwards
 * and expects the environment to follow will differ from glibc; a program that
 * calls putenv and moves on will not. Real code overwhelmingly does the
 * latter, and busybox does.
 *
 * With no '=' POSIX says remove the variable, which is unsetenv's job. */
int putenv(char *string) {
  char name[256];
  long i;
  if (!string) return -1;
  for (i = 0; string[i] && string[i] != '=' && i < (long)sizeof(name) - 1; i++)
    name[i] = string[i];
  if (i >= (long)sizeof(name) - 1) return -1;      /* name too long to isolate */
  name[i] = 0;
  if (!i) return -1;                               /* "=VALUE" has no name */
  if (string[i] != '=') return unsetenv(name);
  pxx_env_load();
  pxx_env_hide(name);
  if (pxx_env_put(name, &string[i + 1]) != 0) { pxx_env_publish(); return -1; }
  pxx_env_publish();
  return 0;
}

/* clearenv(): remove EVERY variable. busybox's `env -i` calls it, which is how
 * it was found -- coreutils/env.c would not compile at all.
 *
 * It must mark the buffer LOADED as well as empty, and that is the whole of
 * the implementation's subtlety: pxx_env_load() is lazy, so setting only the
 * length to 0 leaves pxx_env_loaded == 0 whenever nothing has read the
 * environment yet, and the NEXT getenv() re-reads /proc/self/environ and
 * resurrects everything this was called to remove. Emptied and loaded are two
 * facts here, not one.
 *
 * No pxx_env_hide() loop: hiding mangles names to keep the record structure
 * scannable, which matters when other records must survive. Here none do, so
 * truncating is both correct and what lets a later setenv() reuse the space. */
int clearenv(void) {
  pxx_env_loaded = 1;
  pxx_env_len = 0;
  pxx_env_truncated = 0;                 /* nothing of the startup env survives */
  pxx_env_publish();
  return 0;
}


/* ---- pseudo-terminals -------------------------------------------------------
 *
 * ONE MECHANISM, FIVE NAMES, AND IMPLEMENTING ANY ONE ALONE IS USELESS: the
 * caller gets a master fd it cannot turn into a slave path. On Linux the whole
 * family is an open of /dev/ptmx plus two ioctls and some formatting.
 *
 * Written because busybox calls ptsname_r WITHOUT a guard -- its
 * include/platform.h defines HAVE_PTSNAME_R to 1 by default for a glibc-shaped
 * libc and nothing undefines it -- so there is no fallback arm for us to land
 * in. It is latent rather than live today: the 141-applet configuration does
 * not compile libbb/getpty.c, and telnetd, script and microcom are what reach
 * it. feature-c-crtl-has-no-pty-family-at-all
 */

int posix_openpt(int flags)
{
	return open("/dev/ptmx", flags);
}

/* GRANTPT RETURNS 0 WITHOUT CHECKING ANYTHING, AND THAT IS CORRECT -- BUT THE
 * ZERO IS NOT EVIDENCE ABOUT THE SLAVE'S OWNERSHIP.
 *
 * Historically grantpt ran a setuid helper (pt_chown) to chown/chmod the slave.
 * On any kernel with devpts mounted -- which is every Linux pxx targets -- the
 * mount's own `gid` and `mode` options do that job at allocation time, so there
 * is nothing left for this call to perform and glibc's own implementation is
 * effectively this one. Measured against glibc on this box: grantpt returns 0.
 *
 * The comment exists because "returns 0" and "the permissions were arranged"
 * are different claims and this function can only make the first. A reader who
 * takes the 0 as the second one has been told something we did not check. If a
 * target ever appears without devpts, this is the function that has to grow a
 * real body rather than the one that can stay silent.
 */
int grantpt(int fd)
{
	(void)fd;
	return 0;
}

int unlockpt(int fd)
{
	int zero = 0;

	/* TIOCSPTLCK takes a POINTER to the lock value, not the value. Passing 0
	   directly compiles -- the request is variadic from ioctl's point of
	   view -- and unlocks nothing, which shows up much later as a slave open
	   failing with EIO for no visible reason. */
	return ioctl(fd, TIOCSPTLCK, &zero);
}

/* Returns 0, or the ERROR NUMBER (not -1), and sets errno too -- glibc's
   convention, measured rather than recalled; see the note in <stdlib.h>.

   ERANGE RATHER THAN TRUNCATION when the buffer is too small. A truncated
   "/dev/pts/1" for slave 17 is a path that EXISTS and belongs to another
   session, so silently shortening it hands the caller someone else's terminal.
   The length is therefore computed in full before anything is copied. */
int ptsname_r(int fd, char *buf, size_t buflen)
{
	static const char pre[] = "/dev/pts/";
	char digits[16];
	unsigned int n;
	size_t need, i, d;

	if (buf == 0) {
		errno = EINVAL;
		return EINVAL;
	}
	if (ioctl(fd, TIOCGPTN, &n) < 0) {
		/* errno is already set by ioctl -- ENOTTY for a fd that is not a
		   pty master, which is the case a caller most often hits. */
		return errno;
	}

	/* Format the number backwards into `digits`, so the length is known
	   before a single byte reaches the caller's buffer. */
	d = 0;
	if (n == 0) {
		digits[d++] = '0';
	} else {
		while (n > 0) {
			digits[d++] = (char)('0' + (n % 10u));
			n /= 10u;
		}
	}

	need = (sizeof pre - 1) + d + 1;   /* prefix + digits + NUL */
	if (need > buflen) {
		errno = ERANGE;
		return ERANGE;
	}

	for (i = 0; i < sizeof pre - 1; i++)
		buf[i] = pre[i];
	for (i = 0; i < d; i++)
		buf[(sizeof pre - 1) + i] = digits[d - 1 - i];
	buf[(sizeof pre - 1) + d] = '\0';
	return 0;
}

/* The static-buffer face. 32 bytes holds "/dev/pts/" plus any unsigned int
   ("/dev/pts/4294967295" is 19 characters), so the ERANGE arm above is
   unreachable from here -- it is still checked rather than assumed, because
   the two functions would otherwise have to agree by inspection. */
char *ptsname(int fd)
{
	static char buf[32];

	if (ptsname_r(fd, buf, sizeof buf) != 0)
		return 0;
	return buf;
}

/* ---- multibyte: the C locale and C.UTF-8 ---------------------------------- */

/* Nonzero while LC_CTYPE is C.UTF-8 (setlocale, locale.c). Lives HERE because
   this file is pulled into nearly every C program, and every reader of the flag
   (locale.c, wchar.c, wctype.c, langinfo.c) includes <stdlib.h>, which pulls
   it. feature-crtl-c-utf8-locale */
int __crtl_ctype_utf8;

/* uselocale(3) is per thread and outranks setlocale: 0 = none (the global
   locale applies), 1 = C, 2 = C.UTF-8. toybox selects C.UTF-8 this way
   (uselocale(newlocale(LC_CTYPE_MASK, "C.UTF-8", 0))), not with setlocale. */
/* Guarded like errno (stdio.c): a __thread only where the compiler gives
   thread-locals real storage. Unguarded, every object pulling this file got
   ELF TLS and a PT_TLS, threads or not. */
#ifdef __pxx_thread_local__
static __thread int __crtl_thread_ctype;
#else
static int __crtl_thread_ctype;
#endif

/* THE question every multibyte and wide-character function asks: is this
   thread's LC_CTYPE C.UTF-8? */
int __crtl_utf8(void)
{
  return __crtl_thread_ctype ? __crtl_thread_ctype == 2 : __crtl_ctype_utf8;
}

/* uselocale's half that lives here: the thread's override, old value back;
   k < 0 only reads it */
int __crtl_thread_locale(int k)
{
  int old = __crtl_thread_ctype;
  if (k >= 0) __crtl_thread_ctype = k;
  return old;
}

/* One UTF-8 sequence, glibc's rules (measured, test/c_crtl_utf8_locale.c):
   1..6 bytes, so up to U+7FFFFFFF and NOT capped at U+10FFFF; an overlong form
   and a surrogate are invalid; C0, C1, FE, FF and a stray continuation byte
   are invalid at once. An overlong or surrogate PREFIX is reported as
   incomplete (-2), not invalid, until the sequence is whole -- that is what
   glibc does with "\xE0\x80" and "\xED\xA0".
   Returns the length, 0 for NUL, -1 invalid, -2 incomplete (n too short). */
int __crtl_u8dec(wchar_t *pwc, const char *s, size_t n)
{
  static const unsigned int min[7] = {0, 0, 0x80, 0x800, 0x10000, 0x200000, 0x4000000};
  const unsigned char *u = (const unsigned char *)s;
  unsigned int c = u[0], v;
  int len, i;
  if (n == 0) return -2;
  if (c < 0x80) { if (pwc) *pwc = (wchar_t)c; return c ? 1 : 0; }
  if (c < 0xC2) return -1;
  else if (c < 0xE0) { len = 2; v = c & 0x1F; }
  else if (c < 0xF0) { len = 3; v = c & 0x0F; }
  else if (c < 0xF8) { len = 4; v = c & 0x07; }
  else if (c < 0xFC) { len = 5; v = c & 0x03; }
  else if (c < 0xFE) { len = 6; v = c & 0x01; }
  else return -1;
  for (i = 1; i < len; i++) {
    if ((size_t)i >= n) return -2;
    if ((u[i] & 0xC0) != 0x80) return -1;
    v = (v << 6) | (u[i] & 0x3F);
  }
  if (v < min[len] || (v >= 0xD800 && v <= 0xDFFF)) return -1;
  if (pwc) *pwc = (wchar_t)v;
  return len;
}

/* The encoder: -1 for a negative value (wchar_t is int) and for a surrogate,
   which glibc refuses; everything else up to U+7FFFFFFF encodes. */
int __crtl_u8enc(char *s, wchar_t wc)
{
  unsigned int v = (unsigned int)wc;
  int len, i;
  if (wc < 0 || (v >= 0xD800 && v <= 0xDFFF)) return -1;
  if (v < 0x80) { s[0] = (char)v; return 1; }
  len = v < 0x800 ? 2 : v < 0x10000 ? 3 : v < 0x200000 ? 4 : v < 0x4000000 ? 5 : 6;
  for (i = len - 1; i > 0; i--) { s[i] = (char)(0x80 | (v & 0x3F)); v >>= 6; }
  s[0] = (char)((0xFF00 >> len) | v);
  return len;
}

/* In the C locale every byte above 127 is EILSEQ: glibc's C locale is ASCII,
   see the note in <stdlib.h>. */
int mbtowc(wchar_t *pwc, const char *s, size_t n)
{
  unsigned char c;
  if (!s) return 0;                       /* stateless encoding, either way */
  if (n == 0) return -1;
  if (__crtl_utf8()) {
    int r = __crtl_u8dec(pwc, s, n);
    if (r < 0) { errno = EILSEQ; return -1; }   /* glibc: a short one is -1 too */
    return r;
  }
  c = (unsigned char)*s;
  if (c > 127) { errno = EILSEQ; return -1; }
  if (pwc) *pwc = (wchar_t)c;
  return c ? 1 : 0;
}

int mblen(const char *s, size_t n) { return mbtowc(0, s, n); }

int wctomb(char *s, wchar_t wc)
{
  if (!s) return 0;
  if (__crtl_utf8()) {
    int r = __crtl_u8enc(s, wc);
    if (r < 0) errno = EILSEQ;
    return r;
  }
  if (wc < 0 || wc > 127) { errno = EILSEQ; return -1; }
  *s = (char)wc;
  return 1;
}

/* dst NULL: the length the conversion would have, n ignored (POSIX). */
size_t mbstowcs(wchar_t *dst, const char *src, size_t n)
{
  size_t i = 0;
  if (__crtl_utf8()) {
    for (;;) {
      wchar_t wc;
      int r;
      if (dst && i >= n) return i;
      r = __crtl_u8dec(&wc, src, 6);
      if (r < 0) { errno = EILSEQ; return (size_t)-1; }
      if (dst) dst[i] = wc;
      if (r == 0) return i;
      src += r;
      i++;
    }
  }
  for (;;) {
    unsigned char c = (unsigned char)src[i];
    if (c > 127) { errno = EILSEQ; return (size_t)-1; }
    if (dst) {
      if (i >= n) return i;
      dst[i] = (wchar_t)c;
    }
    if (!c) return i;
    i++;
  }
}

/* dst NULL: the byte count. A character that does not fit whole in what is
   left of dst stops the conversion there, as in glibc. */
size_t wcstombs(char *dst, const wchar_t *src, size_t n)
{
  size_t i = 0;
  if (__crtl_utf8()) {
    for (;; src++) {
      char b[8];
      int r = __crtl_u8enc(b, *src), k;
      if (r < 0) { errno = EILSEQ; return (size_t)-1; }
      if (*src == 0) {
        if (dst && i < n) dst[i] = 0;
        return i;
      }
      if (dst) {
        if (i + (size_t)r > n) return i;
        for (k = 0; k < r; k++) dst[i + k] = b[k];
      }
      i += (size_t)r;
    }
  }
  for (;;) {
    wchar_t wc = src[i];
    if (wc < 0 || wc > 127) { errno = EILSEQ; return (size_t)-1; }
    if (dst) {
      if (i >= n) return i;
      dst[i] = (char)wc;
    }
    if (!wc) return i;
    i++;
  }
}

/* float has no parser of its own: rounding the double gives the correctly
   rounded float except in double-rounding corner cases (a decimal string
   within half a double ulp of a float tie). ERANGE when the double fits but
   the float overflows. */
float strtof(const char *s, char **end)
{
  double d = strtod(s, end);
  float f = (float)d;
  /* a FINITE double too big for float; an infinity strtod parsed from "inf"
     is not an overflow, and one from "1e400" already has its ERANGE */
  if ((d > 3.4028234663852886e38 || d < -3.4028234663852886e38) && d - d == 0) errno = ERANGE;
  return f;
}

/* ---- arc4random, on getentropy --------------------------------------------- */

/* glibc 2.36 reads the kernel each time too (a ChaCha20 buffer came later).
   getentropy takes at most 256 bytes per call. If the kernel refuses there is
   no safe answer, so abort, as OpenBSD's does. */
void arc4random_buf(void *buf, size_t n)
{
  unsigned char *p = (unsigned char *)buf;
  while (n > 0) {
    size_t k = n > 256 ? 256 : n;
    if (getentropy(p, k) != 0) abort();
    p += k;
    n -= k;
  }
}

unsigned int arc4random(void)
{
  unsigned int v;
  arc4random_buf(&v, sizeof v);
  return v;
}

/* Uniform without modulo bias: reject the low (2^32 % upper) values. */
unsigned int arc4random_uniform(unsigned int upper)
{
  unsigned int min, r;
  if (upper < 2) return 0;
  min = (0u - upper) % upper;
  do r = arc4random(); while (r < min);
  return r % upper;
}

/* ---- random_r: glibc's additive feedback generator --------------------------

   The same algorithm, constants and state-buffer layout as glibc's
   stdlib/random_r.c (re-written here, not copied): word -1 of the caller's
   buffer records type and rear position, the rest is the table. TYPE_0 is the
   plain LCG. Checked against glibc's output for the same seed. */

static const int __pxx_rnd_deg[5] = { 0, 7, 15, 31, 63 };
static const int __pxx_rnd_sep[5] = { 0, 3, 1, 3, 1 };

int random_r(struct random_data *buf, int *result)
{
  int *state;
  if (!buf || !result) { errno = EINVAL; return -1; }
  state = buf->state;
  if (buf->rand_type == 0) {
    unsigned int v = ((unsigned int)state[0] * 1103515245u + 12345u) & 0x7fffffffu;
    state[0] = (int)v;
    *result = (int)v;
  } else {
    int *fptr = buf->fptr, *rptr = buf->rptr, *end = buf->end_ptr;
    unsigned int v = (unsigned int)*fptr + (unsigned int)*rptr;
    *fptr = (int)v;
    *result = (int)(v >> 1);
    ++fptr;
    if (fptr >= end) { fptr = state; ++rptr; }
    else { ++rptr; if (rptr >= end) rptr = state; }
    buf->fptr = fptr;
    buf->rptr = rptr;
  }
  return 0;
}

int srandom_r(unsigned int seed, struct random_data *buf)
{
  int type, *state, i, kc, discard;
  long word;
  if (!buf) { errno = EINVAL; return -1; }
  type = buf->rand_type;
  if (type < 0 || type > 4) { errno = EINVAL; return -1; }
  state = buf->state;
  if (seed == 0) seed = 1;
  state[0] = (int)seed;
  if (type == 0) return 0;
  word = (long)(int)seed;
  kc = buf->rand_deg;
  for (i = 1; i < kc; i++) {
    long hi = word / 127773, lo = word % 127773;
    word = 16807 * lo - 2836 * hi;
    if (word < 0) word += 2147483647;
    state[i] = (int)word;
  }
  buf->fptr = &state[buf->rand_sep];
  buf->rptr = &state[0];
  for (i = kc * 10; i > 0; i--) random_r(buf, &discard);
  return 0;
}

static void __pxx_rnd_save(struct random_data *buf)
{
  int *old = buf->state;
  if (!old) return;
  if (buf->rand_type == 0) old[-1] = 0;
  else old[-1] = 5 * (int)(buf->rptr - old) + buf->rand_type;
}

int initstate_r(unsigned int seed, char *statebuf, size_t statelen, struct random_data *buf)
{
  int type, *state;
  if (!buf || !statebuf) { errno = EINVAL; return -1; }
  if (statelen >= 256) type = 4;
  else if (statelen >= 128) type = 3;
  else if (statelen >= 64) type = 2;
  else if (statelen >= 32) type = 1;
  else if (statelen >= 8) type = 0;
  else { errno = EINVAL; return -1; }
  __pxx_rnd_save(buf);
  state = (int *)statebuf + 1;
  buf->rand_type = type;
  buf->rand_deg = __pxx_rnd_deg[type];
  buf->rand_sep = __pxx_rnd_sep[type];
  buf->state = state;
  buf->end_ptr = &state[buf->rand_deg];
  srandom_r(seed, buf);
  state[-1] = type == 0 ? 0 : 5 * (int)(buf->rptr - state) + type;
  return 0;
}

int setstate_r(char *statebuf, struct random_data *buf)
{
  int *state, type, rear;
  if (!buf || !statebuf) { errno = EINVAL; return -1; }
  state = (int *)statebuf + 1;
  type = state[-1] % 5;
  rear = state[-1] / 5;
  if (type < 0 || type > 4) { errno = EINVAL; return -1; }
  __pxx_rnd_save(buf);
  buf->rand_type = type;
  buf->rand_deg = __pxx_rnd_deg[type];
  buf->rand_sep = __pxx_rnd_sep[type];
  buf->state = state;
  if (type != 0) {
    buf->rptr = &state[rear];
    buf->fptr = &state[(rear + buf->rand_sep) % buf->rand_deg];
  }
  buf->end_ptr = &state[buf->rand_deg];
  return 0;
}
