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

size_t wcslen(const wchar_t *s)
{
    const wchar_t *p = s;
    while (*p) p++;
    return (size_t)(p - s);
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
