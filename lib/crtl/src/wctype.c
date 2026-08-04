/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <wctype.h> classification.
 *
 * C locale only, which for these functions is the whole specification: glibc's
 * C locale answers FALSE for every predicate on every value above 127. Verified
 * against a gcc build over -1..255 (all 12 predicates) plus U+0100, U+0391,
 * U+4E00 and U+1F600 — above 127 the pattern is uniformly 000000000000. So the
 * ASCII range is not a subset we are settling for; it is the answer.
 *
 * towlower/towupper live in wchar.c, which <wctype.h> reaches because it
 * includes <wchar.h> first (so src/wchar.c is pulled before this file).
 */

#include <wctype.h>

/* one place where "is this even a byte?" is decided, so WEOF and every wide
   value take the same path out */
static int wc_ascii(wint_t c) { return c >= 0 && c < 128; }

int iswalpha(wint_t c)
{
    if (!wc_ascii(c)) return 0;
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

int iswdigit(wint_t c) { return wc_ascii(c) && c >= '0' && c <= '9'; }

int iswalnum(wint_t c) { return iswalpha(c) || iswdigit(c); }

int iswblank(wint_t c) { return wc_ascii(c) && (c == ' ' || c == '\t'); }

int iswcntrl(wint_t c) { return wc_ascii(c) && (c < 32 || c == 127); }

int iswgraph(wint_t c) { return wc_ascii(c) && c > 32 && c < 127; }

int iswprint(wint_t c) { return wc_ascii(c) && c >= 32 && c < 127; }

int iswlower(wint_t c) { return wc_ascii(c) && c >= 'a' && c <= 'z'; }

int iswupper(wint_t c) { return wc_ascii(c) && c >= 'A' && c <= 'Z'; }

int iswpunct(wint_t c) { return iswgraph(c) && !iswalnum(c); }

int iswspace(wint_t c)
{
    if (!wc_ascii(c)) return 0;
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

int iswxdigit(wint_t c)
{
    if (!wc_ascii(c)) return 0;
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

/* wctype()/iswctype(): the property name is mapped to a small tag, and
   iswctype dispatches on it. The tags are private -- C only promises that a
   value from wctype() is meaningful to iswctype() -- so they need not match
   glibc's, and a program comparing them numerically was already wrong. */
wctype_t wctype(const char *property)
{
    const char *p = property;
    if (!p) return 0;
    if (p[0] == 'a' && p[1] == 'l' && p[2] == 'n') return 1;   /* alnum */
    if (p[0] == 'a' && p[1] == 'l' && p[2] == 'p') return 2;   /* alpha */
    if (p[0] == 'b') return 3;                                  /* blank */
    if (p[0] == 'c') return 4;                                  /* cntrl */
    if (p[0] == 'd') return 5;                                  /* digit */
    if (p[0] == 'g') return 6;                                  /* graph */
    if (p[0] == 'l') return 7;                                  /* lower */
    if (p[0] == 'p' && p[1] == 'r') return 8;                   /* print */
    if (p[0] == 'p' && p[1] == 'u') return 9;                   /* punct */
    if (p[0] == 's') return 10;                                 /* space */
    if (p[0] == 'u') return 11;                                 /* upper */
    if (p[0] == 'x') return 12;                                 /* xdigit */
    return 0;                                                   /* unknown: C says 0 */
}

int iswctype(wint_t c, wctype_t desc)
{
    switch (desc) {
        case 1:  return iswalnum(c);
        case 2:  return iswalpha(c);
        case 3:  return iswblank(c);
        case 4:  return iswcntrl(c);
        case 5:  return iswdigit(c);
        case 6:  return iswgraph(c);
        case 7:  return iswlower(c);
        case 8:  return iswprint(c);
        case 9:  return iswpunct(c);
        case 10: return iswspace(c);
        case 11: return iswupper(c);
        case 12: return iswxdigit(c);
        default: return 0;
    }
}
