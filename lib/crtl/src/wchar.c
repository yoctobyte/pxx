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

/* ---- C.UTF-8: glibc's character tables ------------------------------------
   Generated from glibc's own C.UTF-8 by tools/gen_crtl_unicode.py; read only
   while this thread's LC_CTYPE is C.UTF-8 (__crtl_utf8, stdlib.c). Not built on
   ESP, where setlocale refuses C.UTF-8 instead: about 27 KB of tables is
   flash a microcontroller program should not pay for a locale it cannot
   select from an environment. feature-crtl-c-utf8-locale */
#ifndef __PXX_PLATFORM_ESP__
#include "wchar_unicode.inc"

/* the property word for c (see the .inc header), or 0 = no class, width -1 */
unsigned int __crtl_u8props(wint_t c)
{
  int lo = 0, hi = __U8_NPROPS - 1;
  if (c < 0 || c > 0x10FFFF) return 0;
  while (lo < hi) {                      /* last range starting <= c */
    int mid = (lo + hi + 1) / 2;
    if (__u8_start[mid] <= (unsigned int)c) lo = mid; else hi = mid - 1;
  }
  return __u8_props[lo];
}

static wint_t u8_case(wint_t c, const unsigned int *start, const unsigned short *n,
                      const unsigned char *stride, const int *delta, int count)
{
  int lo = 0, hi = count - 1;
  unsigned int off;
  if (c < 0 || c > 0x10FFFF || count == 0 || (unsigned int)c < start[0]) return c;
  while (lo < hi) {
    int mid = (lo + hi + 1) / 2;
    if (start[mid] <= (unsigned int)c) lo = mid; else hi = mid - 1;
  }
  off = (unsigned int)c - start[lo];
  if (off % stride[lo] == 0 && off / stride[lo] < n[lo]) return c + delta[lo];
  return c;
}
#endif

wint_t towlower(wint_t c)
{
#ifndef __PXX_PLATFORM_ESP__
    if (__crtl_utf8())
        return u8_case(c, __u8_lo_start, __u8_lo_n, __u8_lo_stride, __u8_lo_delta, __U8_NLO);
#endif
    if (c >= 'A' && c <= 'Z')
        return c + ('a' - 'A');
    return c;
}

wint_t towupper(wint_t c)
{
#ifndef __PXX_PLATFORM_ESP__
    if (__crtl_utf8())
        return u8_case(c, __u8_up_start, __u8_up_n, __u8_up_stride, __u8_up_delta, __U8_NUP);
#endif
    if (c >= 'a' && c <= 'z')
        return c - ('a' - 'A');
    return c;
}

#include <errno.h>

/* Under C.UTF-8 a sequence may arrive split across calls; the state keeps the
   bytes seen so far: __count = how many, __value.__wchb = the first four, and
   a fifth (a 6-byte form) in the high byte of __count. The decoder then runs
   over those bytes plus the new ones, so a split sequence is judged exactly
   as a whole one. With no ps, a private state is used, as C requires. */
static mbstate_t __crtl_mbrtowc_state;

size_t mbrtowc(wchar_t *pwc, const char *s, size_t n, mbstate_t *ps)
{
  unsigned char c;
  if (!ps) ps = &__crtl_mbrtowc_state;
  if (!s) { ps->__count = 0; return 0; }   /* reset to the initial state */
  if (n == 0) return (size_t)-2;
  if (__crtl_utf8()) {
    char buf[8];
    int have = ps->__count & 7, i, r;
    size_t take;
    for (i = 0; i < have && i < 4; i++) buf[i] = ps->__value.__wchb[i];
    if (have == 5) buf[4] = (char)((unsigned int)ps->__count >> 24);
    take = n < (size_t)(6 - have) ? n : (size_t)(6 - have);
    for (i = 0; (size_t)i < take; i++) buf[have + i] = s[i];
    r = __crtl_u8dec(pwc, buf, (size_t)have + take);
    if (r == -2) {
      int total = have + (int)take;
      for (i = have; i < total && i < 4; i++) ps->__value.__wchb[i] = buf[i];
      ps->__count = (int)((unsigned int)total |
                    (total == 5 ? (unsigned int)(unsigned char)buf[4] << 24 : 0u));
      return (size_t)-2;
    }
    ps->__count = 0;
    if (r < 0) { errno = EILSEQ; return (size_t)-1; }
    return r == 0 ? 0 : (size_t)(r - have);
  }
  c = (unsigned char)*s;
  if (c > 127) { errno = EILSEQ; return (size_t)-1; }
  if (pwc) *pwc = (wchar_t)c;
  return c ? 1 : 0;
}

size_t wcrtomb(char *s, wchar_t wc, mbstate_t *ps)
{
  if (ps) ps->__count = 0;
  if (!s) return 1;
  if (__crtl_utf8()) {
    int r = __crtl_u8enc(s, wc);
    if (r < 0) { errno = EILSEQ; return (size_t)-1; }
    return (size_t)r;
  }
  if (wc < 0 || wc > 127) { errno = EILSEQ; return (size_t)-1; }
  *s = (char)wc;
  return 1;
}

size_t mbrlen(const char *s, size_t n, mbstate_t *ps)
{
  return mbrtowc(0, s, n, ps);
}

int mbsinit(const mbstate_t *ps) { return !ps || (ps->__count & 7) == 0; }

wint_t btowc(int c) { return (c >= 0 && c < 128) ? (wint_t)c : WEOF; }

int wctob(wint_t c) { return (c >= 0 && c < 128) ? (int)c : -1; }

int wcwidth(wchar_t wc)
{
#ifndef __PXX_PLATFORM_ESP__
  if (__crtl_utf8()) return (int)((__crtl_u8props(wc) >> 12) & 3) - 1;
#endif
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
