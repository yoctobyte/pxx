/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: string / memory helpers.
 *
 * Small, project-owned implementations used by source-backed C libraries.
 * Not a complete hosted libc.
 */

#include <stddef.h>
#include <string.h>

void *memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    while (n > 0) {
        *d++ = *s++;
        n--;
    }
    return dest;
}

void *memmove(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    if (d == s || n == 0)
        return dest;
    if (d < s) {
        while (n > 0) {
            *d++ = *s++;
            n--;
        }
    } else {
        d += n;
        s += n;
        while (n > 0) {
            *--d = *--s;
            n--;
        }
    }
    return dest;
}

void *memset(void *s, int c, size_t n)
{
    unsigned char *p = s;
    unsigned char v = (unsigned char)c;
    while (n > 0) {
        *p++ = v;
        n--;
    }
    return s;
}

int memcmp(const void *s1, const void *s2, size_t n)
{
    const unsigned char *a = s1;
    const unsigned char *b = s2;
    while (n > 0) {
        if (*a != *b)
            return (int)*a - (int)*b;
        a++;
        b++;
        n--;
    }
    return 0;
}

size_t strlen(const char *s)
{
    size_t n = 0;
    while (s[n] != '\0')
        n++;
    return n;
}

/* POSIX. Reads at most `maxlen` bytes and never past them, which is the whole
   point: it is what code uses on a fixed-width field that may not be
   terminated. Returns maxlen when no NUL is found. */
size_t strnlen(const char *s, size_t maxlen)
{
    size_t n = 0;
    while (n < maxlen && s[n] != '\0')
        n++;
    return n;
}

int strcmp(const char *a, const char *b)
{
    while (*a != '\0' && *a == *b) {
        a++;
        b++;
    }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    while (n > 0 && *a != '\0' && *a == *b) {
        a++;
        b++;
        n--;
    }
    if (n == 0)
        return 0;
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

char *strcpy(char *dest, const char *src)
{
    char *d = dest;
    while ((*d++ = *src++) != '\0')
        ;
    return dest;
}

char *strncpy(char *dest, const char *src, size_t n)
{
    char *d = dest;
    while (n > 0 && *src != '\0') {
        *d++ = *src++;
        n--;
    }
    while (n > 0) {
        *d++ = '\0';
        n--;
    }
    return dest;
}

char *strchr(const char *s, int c)
{
    char ch = (char)c;
    while (*s != '\0') {
        if (*s == ch)
            return (char *)s;
        s++;
    }
    if (ch == '\0')
        return (char *)s;
    return NULL;
}

char *strrchr(const char *s, int c)
{
    const char *last = NULL;
    char ch = (char)c;
    do {
        if (*s == ch)
            last = s;
    } while (*s++ != '\0');
    return (char *)last;
}

void *memchr(const void *s, int c, size_t n)
{
    const unsigned char *p = s;
    unsigned char ch = (unsigned char)c;
    while (n > 0) {
        if (*p == ch)
            return (void *)p;
        p++;
        n--;
    }
    return NULL;
}

char *strcat(char *dest, const char *src)
{
    char *d = dest;
    while (*d != '\0')
        d++;
    while ((*d++ = *src++) != '\0')
        ;
    return dest;
}

char *strncat(char *dest, const char *src, size_t n)
{
    char *d = dest;
    while (*d != '\0')
        d++;
    while (n > 0 && *src != '\0') {
        *d++ = *src++;
        n--;
    }
    *d = '\0';
    return dest;
}

size_t strspn(const char *s, const char *accept)
{
    size_t n = 0;
    while (*s != '\0') {
        if (strchr(accept, *s) == NULL)
            break;
        s++;
        n++;
    }
    return n;
}

size_t strcspn(const char *s, const char *reject)
{
    size_t n = 0;
    while (*s != '\0') {
        if (strchr(reject, *s) != NULL)
            break;
        s++;
        n++;
    }
    return n;
}

char *strpbrk(const char *s, const char *accept)
{
    while (*s != '\0') {
        if (strchr(accept, *s) != NULL)
            return (char *)s;
        s++;
    }
    return NULL;
}

char *strstr(const char *haystack, const char *needle)
{
    size_t nlen = strlen(needle);
    if (nlen == 0)
        return (char *)haystack;
    while (*haystack != '\0') {
        if (strncmp(haystack, needle, nlen) == 0)
            return (char *)haystack;
        haystack++;
    }
    return NULL;
}

int strcoll(const char *a, const char *b)
{
    return strcmp(a, b);
}

size_t strxfrm(char *dest, const char *src, size_t n)
{
    size_t len = strlen(src);
    size_t i = 0;
    if (n > 0) {
        while (i + 1 < n && src[i] != '\0') {
            dest[i] = src[i];
            i++;
        }
        dest[i] = '\0';
    }
    return len;
}

/* strerror: the real Linux errno strings, not a stub.
 *
 * This returned the literal "error" for EVERY errnum, which made perror() and
 * strerror_r() useless and left any C program's failure reporting saying
 * nothing at all — "cannot open config: error". The strings below are gcc's
 * verbatim for errno 0..40, which is the range essentially all of them come
 * from; past that it falls back to glibc's own "Unknown error N" wording rather
 * than inventing one, so a diff against gcc stays clean either way.
 *
 * Returns a pointer to static storage, as the standard requires (the caller
 * must not free it), and the out-of-range branch uses a static buffer so the
 * returned pointer stays valid after return. */
static const char *const __pxx_errstr[] = {
  "Success",
  "Operation not permitted",
  "No such file or directory",
  "No such process",
  "Interrupted system call",
  "Input/output error",
  "No such device or address",
  "Argument list too long",
  "Exec format error",
  "Bad file descriptor",
  "No child processes",
  "Resource temporarily unavailable",
  "Cannot allocate memory",
  "Permission denied",
  "Bad address",
  "Block device required",
  "Device or resource busy",
  "File exists",
  "Invalid cross-device link",
  "No such device",
  "Not a directory",
  "Is a directory",
  "Invalid argument",
  "Too many open files in system",
  "Too many open files",
  "Inappropriate ioctl for device",
  "Text file busy",
  "File too large",
  "No space left on device",
  "Illegal seek",
  "Read-only file system",
  "Too many links",
  "Broken pipe",
  "Numerical argument out of domain",
  "Numerical result out of range",
  "Resource deadlock avoided",
  "File name too long",
  "No locks available",
  "Function not implemented",
  "Directory not empty",
  "Too many levels of symbolic links",
  0,   /* 41: glibc has no name here */
  "No message of desired type",
  "Identifier removed",
  "Channel number out of range",
  "Level 2 not synchronized",
  "Level 3 halted",
  "Level 3 reset",
  "Link number out of range",
  "Protocol driver not attached",
  "No CSI structure available",
  "Level 2 halted",
  "Invalid exchange",
  "Invalid request descriptor",
  "Exchange full",
  "No anode",
  "Invalid request code",
  "Invalid slot",
  0,   /* 58: glibc has no name here */
  "Bad font file format",
  "Device not a stream",
  "No data available",
  "Timer expired",
  "Out of streams resources",
  "Machine is not on the network",
  "Package not installed",
  "Object is remote",
  "Link has been severed",
  "Advertise error",
  "Srmount error",
  "Communication error on send",
  "Protocol error",
  "Multihop attempted",
  "RFS specific error",
  "Bad message",
  "Value too large for defined data type",
  "Name not unique on network",
  "File descriptor in bad state",
  "Remote address changed",
  "Can not access a needed shared library",
  "Accessing a corrupted shared library",
  ".lib section in a.out corrupted",
  "Attempting to link in too many shared libraries",
  "Cannot exec a shared library directly",
  "Invalid or incomplete multibyte or wide character",
  "Interrupted system call should be restarted",
  "Streams pipe error",
  "Too many users",
  "Socket operation on non-socket",
  "Destination address required",
  "Message too long",
  "Protocol wrong type for socket",
  "Protocol not available",
  "Protocol not supported",
  "Socket type not supported",
  "Operation not supported",
  "Protocol family not supported",
  "Address family not supported by protocol",
  "Address already in use",
  "Cannot assign requested address",
  "Network is down",
  "Network is unreachable",
  "Network dropped connection on reset",
  "Software caused connection abort",
  "Connection reset by peer",
  "No buffer space available",
  "Transport endpoint is already connected",
  "Transport endpoint is not connected",
  "Cannot send after transport endpoint shutdown",
  "Too many references: cannot splice",
  "Connection timed out",
  "Connection refused",
  "Host is down",
  "No route to host",
  "Operation already in progress",
  "Operation now in progress",
  "Stale file handle",
  "Structure needs cleaning",
  "Not a XENIX named type file",
  "No XENIX semaphores available",
  "Is a named type file",
  "Remote I/O error",
  "Disk quota exceeded",
  "No medium found",
  "Wrong medium type",
  "Operation canceled",
  "Required key not available",
  "Key has expired",
  "Key has been revoked",
  "Key was rejected by service",
  "Owner died",
  "State not recoverable",
  "Operation not possible due to RF-kill",
  "Memory page has hardware error"
};

static char __pxx_errbuf[32];

char *strerror(int errnum)
{
    int n, i, d;
    if (errnum >= 0 && errnum < (int)(sizeof(__pxx_errstr) / sizeof(__pxx_errstr[0])))
        if (__pxx_errstr[errnum])
            return (char *)__pxx_errstr[errnum];
    /* glibc's wording for anything else, built without snprintf */
    memcpy(__pxx_errbuf, "Unknown error ", 14);
    i = 14;
    n = errnum;
    if (n < 0) { __pxx_errbuf[i++] = '-'; n = -n; }
    d = 1;
    while (n / d >= 10) d *= 10;
    while (d > 0) { __pxx_errbuf[i++] = (char)('0' + (n / d) % 10); d /= 10; }
    __pxx_errbuf[i] = 0;
    return __pxx_errbuf;
}

/* strtok_r: reentrant tokenizer. Skips leading delimiters, terminates the token
   with NUL, and advances *saveptr past it. NULL `s` continues from *saveptr.
   Built on strspn/strcspn (delimiter-set skip/scan). */
char *strtok_r(char *s, const char *delim, char **saveptr) {
  char *tok;
  if (s == 0) s = *saveptr;
  s += strspn(s, delim);          /* skip leading delimiters */
  if (*s == 0) { *saveptr = s; return 0; }
  tok = s;
  s += strcspn(s, delim);         /* scan to next delimiter (or end) */
  if (*s != 0) { *s = 0; s++; }   /* terminate token, step past delimiter */
  *saveptr = s;
  return tok;
}

/* strtok: classic non-reentrant tokenizer over a static save-pointer. */
static char *__pxx_strtok_save;
char *strtok(char *s, const char *delim) {
  return strtok_r(s, delim, &__pxx_strtok_save);
}

/* ---- the assumed-libc batch (feature-crtl-libc-gap-batch-2026-08) ----------
 * Found by a differential probe against gcc rather than by waiting for a
 * corpus to trip them: real C reaches for all of these routinely.
 */

/* stpcpy: like strcpy but returns a pointer to the destination's NUL rather
 * than to its start — the whole reason to use it, since it lets a caller chain
 * appends without re-walking what it just wrote. */
char *stpcpy(char *dest, const char *src) {
  while ((*dest = *src) != 0) { dest++; src++; }
  return dest;                    /* the NUL, not the start */
}

/* memccpy: copy at most n bytes, stopping AFTER the first occurrence of c.
 * Returns the byte past that copy of c, or NULL if c never appeared. */
void *memccpy(void *dest, const void *src, int c, size_t n) {
  unsigned char *d = (unsigned char *)dest;
  const unsigned char *s = (const unsigned char *)src;
  unsigned char t = (unsigned char)c;
  size_t i;
  for (i = 0; i < n; i++) {
    d[i] = s[i];
    if (s[i] == t) return &d[i + 1];
  }
  return 0;
}

/* memrchr: last occurrence of c in the first n bytes. Walks backwards, so an
 * n of 0 must not index at all. */
void *memrchr(const void *s, int c, size_t n) {
  const unsigned char *p = (const unsigned char *)s;
  unsigned char t = (unsigned char)c;
  while (n > 0) {
    n--;
    if (p[n] == t) return (void *)&p[n];
  }
  return 0;
}

/* strsep: the reentrant strtok replacement, and NOT equivalent to it — strsep
 * returns an EMPTY token for two adjacent delimiters where strtok skips them,
 * which is the behaviour parsers of ':'-separated fields depend on. Advances
 * *stringp past the delimiter, or sets it to NULL at the end. */
char *strsep(char **stringp, const char *delim) {
  char *s = *stringp;
  char *p;
  if (!s) return 0;
  p = s + strcspn(s, delim);
  if (*p) { *p = 0; *stringp = p + 1; }
  else *stringp = 0;
  return s;
}

/* strcasestr: strstr ignoring ASCII case. Not locale-aware, matching what the
 * GNU version does for the ASCII range that callers actually use. */
static int __pxx_lc(int ch) {
  if (ch >= 'A' && ch <= 'Z') return ch + 32;
  return ch;
}
char *strcasestr(const char *haystack, const char *needle) {
  size_t i, j;
  if (!*needle) return (char *)haystack;
  for (i = 0; haystack[i]; i++) {
    for (j = 0; needle[j]; j++)
      if (__pxx_lc((unsigned char)haystack[i + j]) != __pxx_lc((unsigned char)needle[j]))
        break;
    if (!needle[j]) return (char *)&haystack[i];
  }
  return 0;
}

/* strerror_r: the XSI form — writes into the caller's buffer and returns 0, or
 * ERANGE when it does not fit. NOT the GNU form (which returns char* and may
 * ignore the buffer); the two disagree on the return type, and code that tests
 * the result as an int is the common case. Always NUL-terminates on success. */
int strerror_r(int errnum, char *buf, size_t buflen) {
  const char *e = strerror(errnum);
  size_t n = strlen(e);
  if (!buf || buflen == 0) return 34;      /* ERANGE */
  if (n + 1 > buflen) return 34;
  memcpy(buf, e, n + 1);
  return 0;
}

/* ---- GNU extensions ------------------------------------------------------- */

/* mempcpy returns the END of the copy (dest + n), which is what makes it worth
   having: chained appends need no running offset. Same copy semantics as
   memcpy — the regions must not overlap. */
void *mempcpy(void *dest, const void *src, size_t n) {
  memcpy(dest, src, n);
  return (char *)dest + n;
}

/* stpncpy: strncpy's return value, fixed. strncpy returns dest (useless);
   stpncpy returns a pointer to the NUL it wrote, or to dest+n when the source
   did not fit. Like strncpy it PADS the remainder with NULs. */
char *stpncpy(char *dest, const char *src, size_t n) {
  size_t i = 0;
  while (i < n && src[i]) { dest[i] = src[i]; i++; }
  { size_t j = i; while (j < n) dest[j++] = 0; }
  return dest + i;
}

/* strchrnul: strchr that returns the terminating NUL instead of NULL when the
   character is absent, so the result is always dereferenceable and the caller
   needs no branch. Searching for '\0' finds the terminator, as in strchr. */
char *strchrnul(const char *s, int c) {
  char ch = (char)c;
  while (*s && *s != ch) s++;
  return (char *)s;
}

/* rawmemchr: memchr with no bound, for when the byte is KNOWN to be present.
   Undefined if it is not — that is the contract, and the speed is the point. */
void *rawmemchr(const void *s, int c) {
  const unsigned char *p = (const unsigned char *)s;
  unsigned char ch = (unsigned char)c;
  while (*p != ch) p++;
  return (void *)p;
}

/* memmem: the substring search, for bytes rather than strings. An empty needle
   matches at the start, as in glibc. Naive O(n*m); correctness first. */
void *memmem(const void *hay, size_t haylen, const void *ned, size_t nedlen) {
  const unsigned char *h = (const unsigned char *)hay;
  const unsigned char *n = (const unsigned char *)ned;
  size_t i, j;
  if (nedlen == 0) return (void *)h;
  if (nedlen > haylen) return 0;
  for (i = 0; i + nedlen <= haylen; i++) {
    for (j = 0; j < nedlen; j++) if (h[i + j] != n[j]) break;
    if (j == nedlen) return (void *)(h + i);
  }
  return 0;
}

/* strverscmp: strcmp, except that a run of digits compares as a NUMBER, so
   "file9" sorts before "file10". glibc's rule, which is subtler than "compare
   the integers": a digit run with LEADING ZEROS is a fractional part and sorts
   BEFORE one without, so "file.01" < "file.1". We reproduce that, because the
   callers that reach for this function are the ones that care about it. */
static int pxx_isdig(unsigned char c) { return c >= '0' && c <= '9'; }

int strverscmp(const char *a, const char *b) {
  const unsigned char *p = (const unsigned char *)a;
  const unsigned char *q = (const unsigned char *)b;

  while (*p && *p == *q) { p++; q++; }

  /* Back up over any digit run we walked INTO, so the comparison sees whole
     numbers: "file10" vs "file9" diverges at '1' vs '9', mid-number. */
  if (pxx_isdig(*p) || pxx_isdig(*q)) {
    const unsigned char *sp = p, *sq = q;
    while (sp > (const unsigned char *)a && pxx_isdig(sp[-1])) { sp--; sq--; }
    if (pxx_isdig(*sp) && pxx_isdig(*sq)) {
      int za = (*sp == '0'), zb = (*sq == '0');
      if (za || zb) {
        /* fractional: leading zeros sort first, then plain lexicographic */
        if (za != zb) return za ? -1 : 1;
        return (int)*p - (int)*q;
      }
      { const unsigned char *ea = sp, *eb = sq;
        while (pxx_isdig(*ea)) ea++;
        while (pxx_isdig(*eb)) eb++;
        if (ea - sp != eb - sq) return (ea - sp) < (eb - sq) ? -1 : 1; }
      return (int)*p - (int)*q;
    }
  }
  return (int)*p - (int)*q;
}
