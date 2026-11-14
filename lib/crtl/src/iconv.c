/* SPDX-License-Identifier: Zlib */
/* C runtime: iconv over a decode-to-code-point / encode pair (see <iconv.h>). */
#include <iconv.h>
#include <stdlib.h>
#include <errno.h>

enum { CS_UTF8 = 1, CS_UTF16LE, CS_UTF16BE, CS_UTF32LE, CS_UTF32BE, CS_ASCII, CS_LATIN1 };

struct crtl_iconv { int from, to; };

static int cs_lookup(const char *n)
{
  static const struct { const char *name; int cs; } tab[] = {
    { "utf8", CS_UTF8 }, { "utf16le", CS_UTF16LE }, { "utf16be", CS_UTF16BE },
    { "utf32le", CS_UTF32LE }, { "utf32be", CS_UTF32BE },
    { "ucs4le", CS_UTF32LE }, { "ucs4be", CS_UTF32BE }, { "wchart", CS_UTF32LE },
    { "ascii", CS_ASCII }, { "usascii", CS_ASCII }, { "ansix3.41968", CS_ASCII },
    { "iso88591", CS_LATIN1 }, { "latin1", CS_LATIN1 }, { "l1", CS_LATIN1 },
    { 0, 0 }
  };
  char k[32];
  int i = 0, j;
  for (; *n && *n != '/' && i < 31; n++) {   /* stop at //TRANSLIT etc. */
    char c = *n;
    if (c == '-' || c == '_') continue;
    if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
    k[i++] = c;
  }
  k[i] = 0;
  for (j = 0; tab[j].name; j++) {
    const char *a = tab[j].name, *b = k;
    while (*a && *a == *b) { a++; b++; }
    if (!*a && !*b) return tab[j].cs;
  }
  return 0;
}

iconv_t iconv_open(const char *tocode, const char *fromcode)
{
  struct crtl_iconv *cd;
  int t = cs_lookup(tocode), f = cs_lookup(fromcode);
  if (!t || !f) { errno = EINVAL; return (iconv_t)-1; }
  cd = (struct crtl_iconv *)malloc(sizeof *cd);
  if (!cd) { errno = ENOMEM; return (iconv_t)-1; }
  cd->from = f;
  cd->to = t;
  return (iconv_t)cd;
}

int iconv_close(iconv_t cd)
{
  free(cd);
  return 0;
}

/* Decode one character. Returns its length in bytes, 0 when the input ends
   inside it (EINVAL), or -1 for an invalid sequence (EILSEQ). */
static int dec(int cs, const unsigned char *p, size_t n, unsigned long *cp)
{
  unsigned long c;
  int len, i;
  switch (cs) {
  case CS_ASCII:
    if (p[0] > 127) return -1;
    *cp = p[0]; return 1;
  case CS_LATIN1:
    *cp = p[0]; return 1;
  case CS_UTF8:
    c = p[0];
    if (c < 0x80) { *cp = c; return 1; }
    if (c < 0xC2) return -1;
    if (c < 0xE0) { len = 2; c &= 0x1F; }
    else if (c < 0xF0) { len = 3; c &= 0x0F; }
    else if (c < 0xF5) { len = 4; c &= 0x07; }
    else return -1;
    for (i = 1; i < len; i++) {
      if ((size_t)i >= n) return 0;
      if ((p[i] & 0xC0) != 0x80) return -1;
      c = (c << 6) | (p[i] & 0x3F);
    }
    if ((len == 3 && c < 0x800) || (len == 4 && (c < 0x10000 || c > 0x10FFFF)) ||
        (c >= 0xD800 && c <= 0xDFFF)) return -1;
    *cp = c; return len;
  case CS_UTF16LE: case CS_UTF16BE: {
    int be = cs == CS_UTF16BE;
    unsigned long lo;
    if (n < 2) return 0;
    c = be ? ((unsigned long)p[0] << 8 | p[1]) : ((unsigned long)p[1] << 8 | p[0]);
    if (c >= 0xDC00 && c <= 0xDFFF) return -1;
    if (c < 0xD800 || c > 0xDBFF) { *cp = c; return 2; }
    if (n < 4) return 0;
    lo = be ? ((unsigned long)p[2] << 8 | p[3]) : ((unsigned long)p[3] << 8 | p[2]);
    if (lo < 0xDC00 || lo > 0xDFFF) return -1;
    *cp = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
    return 4;
  }
  case CS_UTF32LE: case CS_UTF32BE:
    if (n < 4) return 0;
    if (cs == CS_UTF32BE)
      c = (unsigned long)p[0] << 24 | (unsigned long)p[1] << 16 | (unsigned long)p[2] << 8 | p[3];
    else
      c = (unsigned long)p[3] << 24 | (unsigned long)p[2] << 16 | (unsigned long)p[1] << 8 | p[0];
    if (c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) return -1;
    *cp = c; return 4;
  }
  return -1;
}

/* Encode one code point into o (room for 4 bytes). Returns the length, or -1
   when the target set has no such character. */
static int enc(int cs, unsigned long c, unsigned char *o)
{
  switch (cs) {
  case CS_ASCII:  if (c > 127) return -1; o[0] = (unsigned char)c; return 1;
  case CS_LATIN1: if (c > 255) return -1; o[0] = (unsigned char)c; return 1;
  case CS_UTF8:
    if (c < 0x80) { o[0] = (unsigned char)c; return 1; }
    if (c < 0x800) { o[0] = (unsigned char)(0xC0 | c >> 6); o[1] = (unsigned char)(0x80 | (c & 0x3F)); return 2; }
    if (c < 0x10000) {
      o[0] = (unsigned char)(0xE0 | c >> 12); o[1] = (unsigned char)(0x80 | ((c >> 6) & 0x3F));
      o[2] = (unsigned char)(0x80 | (c & 0x3F)); return 3;
    }
    o[0] = (unsigned char)(0xF0 | c >> 18); o[1] = (unsigned char)(0x80 | ((c >> 12) & 0x3F));
    o[2] = (unsigned char)(0x80 | ((c >> 6) & 0x3F)); o[3] = (unsigned char)(0x80 | (c & 0x3F));
    return 4;
  case CS_UTF16LE: case CS_UTF16BE: {
    unsigned long u[2];
    int k = 1, i;
    if (c >= 0x10000) { c -= 0x10000; u[0] = 0xD800 + (c >> 10); u[1] = 0xDC00 + (c & 0x3FF); k = 2; }
    else u[0] = c;
    for (i = 0; i < k; i++) {
      unsigned char hi = (unsigned char)(u[i] >> 8), lo = (unsigned char)u[i];
      o[2 * i]     = cs == CS_UTF16BE ? hi : lo;
      o[2 * i + 1] = cs == CS_UTF16BE ? lo : hi;
    }
    return 2 * k;
  }
  case CS_UTF32LE:
    o[0] = (unsigned char)c; o[1] = (unsigned char)(c >> 8); o[2] = (unsigned char)(c >> 16); o[3] = 0;
    return 4;
  case CS_UTF32BE:
    o[3] = (unsigned char)c; o[2] = (unsigned char)(c >> 8); o[1] = (unsigned char)(c >> 16); o[0] = 0;
    return 4;
  }
  return -1;
}

size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft,
             char **outbuf, size_t *outbytesleft)
{
  struct crtl_iconv *c = (struct crtl_iconv *)cd;
  if (!inbuf || !*inbuf) return 0;     /* reset: every converter here is stateless */
  while (*inbytesleft) {
    unsigned long cp;
    unsigned char tmp[4];
    int il = dec(c->from, (const unsigned char *)*inbuf, *inbytesleft, &cp), ol, i;
    if (il == 0) { errno = EINVAL; return (size_t)-1; }
    if (il < 0) { errno = EILSEQ; return (size_t)-1; }
    ol = enc(c->to, cp, tmp);
    if (ol < 0) { errno = EILSEQ; return (size_t)-1; }
    if ((size_t)ol > *outbytesleft) { errno = E2BIG; return (size_t)-1; }
    for (i = 0; i < ol; i++) (*outbuf)[i] = (char)tmp[i];
    *outbuf += ol; *outbytesleft -= (size_t)ol;
    *inbuf += il; *inbytesleft -= (size_t)il;
  }
  return 0;
}
