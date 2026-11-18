/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <wchar.h>.
 *
 * wchar_t is 32-bit here (see the header), so wcslen is a plain scan for the
 * terminating zero — no encoding is involved and it is exact.
 *
 * towlower/towupper are ASCII-only, which is not a simplification: crtl is
 * C-locale-only, and glibc's C locale does exactly this. Verified against a gcc
 * build over the whole range -1..255 plus U+0100, U+0391, U+4E00 and U+1F600 —
 * every value above 127 is returned unchanged, and WEOF (-1) passes through.
 *
 * These were declared in <wchar.h> and <wctype.h> but implemented nowhere, so
 * a program calling one imported it from glibc and stopped being statically
 * linked — the same declared-but-unreachable shape as
 * bug-cfront-spurious-dt-needed-libc-with-no-imports, which is how it was
 * found (test/cwide_string_literal imported wcslen).
 */

#include <wchar.h>
#include <stdlib.h>

size_t wcslen(const wchar_t *s)
{
    const wchar_t *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

size_t wcsnlen(const wchar_t *s, size_t maxlen)
{
    size_t n = 0;
    while (n < maxlen && s[n]) n++;
    return n;
}

wchar_t *wcschr(const wchar_t *s, wchar_t c)
{
    for (;; s++) {
        if (*s == c) return (wchar_t *)s;
        if (!*s) return 0;
    }
}

wchar_t *wcsrchr(const wchar_t *s, wchar_t c)
{
    const wchar_t *r = 0;
    for (;; s++) {
        if (*s == c) r = s;
        if (!*s) return (wchar_t *)r;
    }
}

/* wchar_t is signed here, as in glibc: the comparison is of the values */
int wcscmp(const wchar_t *a, const wchar_t *b)
{
    while (*a && *a == *b) { a++; b++; }
    return *a < *b ? -1 : *a > *b;
}

int wcsncmp(const wchar_t *a, const wchar_t *b, size_t n)
{
    for (; n; n--, a++, b++) {
        if (*a != *b) return *a < *b ? -1 : 1;
        if (!*a) return 0;
    }
    return 0;
}

wchar_t *wcscpy(wchar_t *d, const wchar_t *s)
{
    wchar_t *r = d;
    while ((*d++ = *s++)) ;
    return r;
}

wchar_t *wcsncpy(wchar_t *d, const wchar_t *s, size_t n)
{
    size_t i = 0;
    for (; i < n && s[i]; i++) d[i] = s[i];
    for (; i < n; i++) d[i] = 0;
    return d;
}

wchar_t *wcscat(wchar_t *d, const wchar_t *s)
{
    wcscpy(d + wcslen(d), s);
    return d;
}

wchar_t *wcsncat(wchar_t *d, const wchar_t *s, size_t n)
{
    wchar_t *p = d + wcslen(d);
    while (n-- && *s) *p++ = *s++;
    *p = 0;
    return d;
}

size_t wcsspn(const wchar_t *s, const wchar_t *accept)
{
    size_t n = 0;
    while (s[n] && wcschr(accept, s[n])) n++;
    return n;
}

size_t wcscspn(const wchar_t *s, const wchar_t *reject)
{
    size_t n = 0;
    while (s[n] && !wcschr(reject, s[n])) n++;
    return n;
}

wchar_t *wcspbrk(const wchar_t *s, const wchar_t *accept)
{
    s += wcscspn(s, accept);
    return *s ? (wchar_t *)s : 0;
}

wchar_t *wcsstr(const wchar_t *hay, const wchar_t *needle)
{
    size_t n = wcslen(needle);
    if (!n) return (wchar_t *)hay;
    for (; *hay; hay++)
        if (*hay == *needle && !wmemcmp(hay, needle, n)) return (wchar_t *)hay;
    return 0;
}

wchar_t *wcsdup(const wchar_t *s)
{
    size_t n = wcslen(s) + 1;
    wchar_t *d = malloc(n * sizeof *d);
    return d ? wmemcpy(d, s, n) : 0;
}

wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n)
{
    for (; n; n--, s++) if (*s == c) return (wchar_t *)s;
    return 0;
}

int wmemcmp(const wchar_t *a, const wchar_t *b, size_t n)
{
    for (; n; n--, a++, b++) if (*a != *b) return *a < *b ? -1 : 1;
    return 0;
}

wchar_t *wmemcpy(wchar_t *d, const wchar_t *s, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++) d[i] = s[i];
    return d;
}

wchar_t *wmemmove(wchar_t *d, const wchar_t *s, size_t n)
{
    size_t i;
    if (d < s) for (i = 0; i < n; i++) d[i] = s[i];
    else for (i = n; i; i--) d[i - 1] = s[i - 1];
    return d;
}

wchar_t *wmemset(wchar_t *d, wchar_t c, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++) d[i] = c;
    return d;
}

wint_t towlower(wint_t c)
{
    if (c >= 'A' && c <= 'Z')
        return c + ('a' - 'A');
    return c;
}

wint_t towupper(wint_t c)
{
    if (c >= 'a' && c <= 'z')
        return c - ('a' - 'A');
    return c;
}

#include <errno.h>

size_t mbrtowc(wchar_t *pwc, const char *s, size_t n, mbstate_t *ps)
{
  unsigned char c;
  (void)ps;
  if (!s) return 0;               /* reset to the initial state: stateless */
  if (n == 0) return (size_t)-2;
  c = (unsigned char)*s;
  if (c > 127) { errno = EILSEQ; return (size_t)-1; }
  if (pwc) *pwc = (wchar_t)c;
  return c ? 1 : 0;
}

size_t wcrtomb(char *s, wchar_t wc, mbstate_t *ps)
{
  (void)ps;
  if (!s) return 1;
  if (wc < 0 || wc > 127) { errno = EILSEQ; return (size_t)-1; }
  *s = (char)wc;
  return 1;
}

size_t mbrlen(const char *s, size_t n, mbstate_t *ps)
{
  return mbrtowc(0, s, n, ps);
}

int mbsinit(const mbstate_t *ps) { (void)ps; return 1; }

wint_t btowc(int c) { return (c >= 0 && c < 128) ? (wint_t)c : WEOF; }

int wctob(wint_t c) { return (c >= 0 && c < 128) ? (int)c : -1; }

int wcwidth(wchar_t wc)
{
  if (wc == 0) return 0;
  if (wc >= 32 && wc < 127) return 1;
  return -1;
}

int wcswidth(const wchar_t *s, size_t n)
{
  int w = 0;
  for (; n && *s; s++, n--) {
    int k = wcwidth(*s);
    if (k < 0) return -1;
    w += k;
  }
  return w;
}
