/* SPDX-License-Identifier: Zlib */
/* src/printf.c (<printf.h>; crtl pairs src/<header>.c with its header): parse_printf_format, from the glibc manual; the length modifiers map as
   glibc's do on x86-64, measured by test/c_printf_h.c (see the length
   loop). feature-crtl-printf-h-parse-printf-format */
#include <printf.h>

/* "%N$" or "*N$": a 1-based position, or 0 when there is none (p unmoved). */
static size_t crtl_pf_pos(const char **pp)
{
  const char *p = *pp;
  size_t v = 0;
  if (*p < '1' || *p > '9') return 0;
  while (*p >= '0' && *p <= '9') v = v * 10 + (size_t)(*p++ - '0');
  if (*p != '$') return 0;
  *pp = p + 1;
  return v;
}

static void crtl_pf_put(int *argtypes, size_t n, size_t idx, int t)
{
  if (idx < n) argtypes[idx] = t;
}

size_t parse_printf_format(const char *fmt, size_t n, int *argtypes)
{
  size_t next = 0, max = 0;
  const char *p = fmt;
  while (*p) {
    size_t pos, at;
    int flags = 0, t, hh = 0, ldbl = 0;
    if (*p++ != '%') continue;
    if (*p == '%') { p++; continue; }
    pos = crtl_pf_pos(&p);
    while (*p == '-' || *p == '+' || *p == ' ' || *p == '#' || *p == '0' || *p == '\'' || *p == 'I') p++;
    /* width */
    if (*p == '*') {
      size_t wp;
      p++;
      wp = crtl_pf_pos(&p);
      at = wp ? wp - 1 : next++;
      crtl_pf_put(argtypes, n, at, PA_INT);
      if (at + 1 > max) max = at + 1;
    } else {
      while (*p >= '0' && *p <= '9') p++;
    }
    /* precision */
    if (*p == '.') {
      p++;
      if (*p == '*') {
        size_t pp;
        p++;
        pp = crtl_pf_pos(&p);
        at = pp ? pp - 1 : next++;
        crtl_pf_put(argtypes, n, at, PA_INT);
        if (at + 1 > max) max = at + 1;
      } else {
        while (*p >= '0' && *p <= '9') p++;
      }
    }
    /* length. Mapped as glibc 2.4x does on x86-64, measured by
       test/c_printf_h.c: l, ll, j, z, Z and t give PA_FLAG_LONG (all are
       long-sized); q and L give no flag on an integer conversion but
       PA_FLAG_LONG_DOUBLE on a floating one, as does ll; %lc and %ls stay PA_CHAR and
       PA_STRING; every %n is PA_INT|PA_FLAG_PTR whatever its length. */
    for (;;) {
      if (*p == 'h') { if (flags & PA_FLAG_SHORT) { hh = 1; flags &= ~PA_FLAG_SHORT; } else if (!hh) flags |= PA_FLAG_SHORT; p++; }
      else if (*p == 'l' && p[1] == 'l') { flags |= PA_FLAG_LONG; ldbl = 1; p += 2; }
      else if (*p == 'l' || *p == 'j' || *p == 'z' || *p == 'Z' || *p == 't') { flags |= PA_FLAG_LONG; p++; }
      else if (*p == 'L' || *p == 'q') { ldbl = 1; p++; }
      else break;
    }
    switch (*p) {
    case 'd': case 'i': case 'o': case 'u': case 'x': case 'X':
      t = hh ? PA_CHAR : PA_INT | flags; break;
    case 'c': t = PA_CHAR; break;
    case 'C': t = PA_WCHAR; break;
    case 's': t = PA_STRING; break;
    case 'S': t = PA_WSTRING; break;
    case 'p': t = PA_POINTER; break;
    case 'n': t = PA_INT | PA_FLAG_PTR; break;
    case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': case 'a': case 'A':
      t = PA_DOUBLE | (ldbl ? PA_FLAG_LONG_DOUBLE : 0); break;
    case '\0':
      continue;
    default:          /* %m and unknown conversions take no argument */
      p++; continue;
    }
    p++;
    at = pos ? pos - 1 : next++;
    crtl_pf_put(argtypes, n, at, t);
    if (at + 1 > max) max = at + 1;
  }
  return max;
}
