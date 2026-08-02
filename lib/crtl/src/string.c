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

char *strerror(int errnum)
{
    (void)errnum;
    return "error";
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
