/* SPDX-License-Identifier: Zlib */
/* <uchar.h> conversions over crtl's C-locale mbrtowc/wcrtomb.
   feature-crtl-uchar-h */
#include <uchar.h>
#include <wchar.h>
#include <errno.h>

static mbstate_t crtl_uchar_state16, crtl_uchar_state16w, crtl_uchar_state32;

size_t mbrtoc32(char32_t *pc32, const char *s, size_t n, mbstate_t *ps)
{
  wchar_t wc;
  size_t r;
  if (!ps) ps = &crtl_uchar_state32;
  if (!s) return mbrtowc(0, "", 1, ps);
  r = mbrtowc(&wc, s, n, ps);
  if (r <= n && pc32) *pc32 = (char32_t)wc;
  return r;
}

size_t c32rtomb(char *s, char32_t c32, mbstate_t *ps)
{
  if (!ps) ps = &crtl_uchar_state32;
  return wcrtomb(s, (wchar_t)c32, ps);
}

/* Every character the C locale can produce is in the BMP and not a
   surrogate, so mbrtoc16 never has the second half of a pair to hand out. */
size_t mbrtoc16(char16_t *pc16, const char *s, size_t n, mbstate_t *ps)
{
  wchar_t wc;
  size_t r;
  if (!ps) ps = &crtl_uchar_state16;
  if (!s) return mbrtowc(0, "", 1, ps);
  r = mbrtowc(&wc, s, n, ps);
  if (r <= n && pc16) *pc16 = (char16_t)wc;
  return r;
}

/* A high surrogate is held in ps->__value.__wch (bit 31 marks it held) and
   nothing is written; the low one completes the code point. A lone low
   surrogate, or a high one not followed by a low one, is EILSEQ. */
size_t c16rtomb(char *s, char16_t c16, mbstate_t *ps)
{
  unsigned int held;
  if (!ps) ps = &crtl_uchar_state16w;
  if (!s) { ps->__value.__wch = 0; return 1; }
  held = ps->__value.__wch;
  if (c16 >= 0xD800 && c16 <= 0xDBFF) {
    if (held & 0x80000000u) { errno = EILSEQ; return (size_t)-1; }
    ps->__value.__wch = 0x80000000u | (unsigned int)(c16 - 0xD800);
    return 0;
  }
  if (c16 >= 0xDC00 && c16 <= 0xDFFF) {
    unsigned int cp;
    if (!(held & 0x80000000u)) { errno = EILSEQ; return (size_t)-1; }
    ps->__value.__wch = 0;
    cp = 0x10000u + ((held & 0x3FFu) << 10) + (unsigned int)(c16 - 0xDC00);
    return wcrtomb(s, (wchar_t)cp, ps);
  }
  if (held & 0x80000000u) { ps->__value.__wch = 0; errno = EILSEQ; return (size_t)-1; }
  return wcrtomb(s, (wchar_t)c16, ps);
}
