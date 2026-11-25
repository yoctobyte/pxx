/* SPDX-License-Identifier: Zlib */
/* C runtime: iconv over a decode-to-code-point / encode pair (see <iconv.h>). */
#include <iconv.h>
#include <stdlib.h>
#include <errno.h>

enum { CS_UTF8 = 1, CS_UTF16LE, CS_UTF16BE, CS_UTF32LE, CS_UTF32BE, CS_ASCII, CS_LATIN1,
       CS_CP437, CS_CP850 };

/* The DOS code pages FAT file systems name their short names in: CP437 (the
   original IBM PC set) and CP850 (DOS Latin-1), which mkfs.fat and fsck.fat
   (dosfstools) open by default. The low half is ASCII in both; these are the
   high halves, the same mapping as glibc's IBM437/IBM850 converters (checked
   byte by byte, both directions). Without them iconv_open failed and
   mkfs.fat fell back to its own table with three lines of complaint. */
static const unsigned short cp437_hi[128] = {
  0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7,
  0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
  0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9,
  0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
  0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA,
  0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
  0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
  0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
  0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
  0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
  0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
  0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
  0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4,
  0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
  0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248,
  0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0,
};
static const unsigned short cp850_hi[128] = {
  0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7,
  0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
  0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9,
  0x00FF, 0x00D6, 0x00DC, 0x00F8, 0x00A3, 0x00D8, 0x00D7, 0x0192,
  0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA,
  0x00BF, 0x00AE, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
  0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x00C1, 0x00C2, 0x00C0,
  0x00A9, 0x2563, 0x2551, 0x2557, 0x255D, 0x00A2, 0x00A5, 0x2510,
  0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x00E3, 0x00C3,
  0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x00A4,
  0x00F0, 0x00D0, 0x00CA, 0x00CB, 0x00C8, 0x0131, 0x00CD, 0x00CE,
  0x00CF, 0x2518, 0x250C, 0x2588, 0x2584, 0x00A6, 0x00CC, 0x2580,
  0x00D3, 0x00DF, 0x00D4, 0x00D2, 0x00F5, 0x00D5, 0x00B5, 0x00FE,
  0x00DE, 0x00DA, 0x00DB, 0x00D9, 0x00FD, 0x00DD, 0x00AF, 0x00B4,
  0x00AD, 0x00B1, 0x2017, 0x00BE, 0x00B6, 0x00A7, 0x00F7, 0x00B8,
  0x00B0, 0x00A8, 0x00B7, 0x00B9, 0x00B3, 0x00B2, 0x25A0, 0x00A0,
};

static const unsigned short *cs_hi(int cs)
{
  return cs == CS_CP437 ? cp437_hi : cp850_hi;
}

struct crtl_iconv { int from, to; };

static int cs_lookup(const char *n)
{
  static const struct { const char *name; int cs; } tab[] = {
    { "utf8", CS_UTF8 }, { "utf16le", CS_UTF16LE }, { "utf16be", CS_UTF16BE },
    { "utf32le", CS_UTF32LE }, { "utf32be", CS_UTF32BE },
    { "ucs4le", CS_UTF32LE }, { "ucs4be", CS_UTF32BE }, { "wchart", CS_UTF32LE },
    { "ascii", CS_ASCII }, { "usascii", CS_ASCII }, { "ansix3.41968", CS_ASCII },
    { "iso88591", CS_LATIN1 }, { "latin1", CS_LATIN1 }, { "l1", CS_LATIN1 },
    { "cp437", CS_CP437 }, { "ibm437", CS_CP437 }, { "437", CS_CP437 },
    { "cp850", CS_CP850 }, { "ibm850", CS_CP850 }, { "850", CS_CP850 },
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
  case CS_CP437: case CS_CP850:
    *cp = p[0] < 128 ? p[0] : cs_hi(cs)[p[0] - 128]; return 1;
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
  case CS_CP437: case CS_CP850: {
    const unsigned short *t = cs_hi(cs);
    int i;
    if (c < 128) { o[0] = (unsigned char)c; return 1; }
    for (i = 0; i < 128; i++)
      if (t[i] == c) { o[0] = (unsigned char)(128 + i); return 1; }
    return -1;
  }
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
