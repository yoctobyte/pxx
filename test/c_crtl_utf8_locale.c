/* The C.UTF-8 locale, against gcc+glibc (feature-crtl-c-utf8-locale).
 *
 * What toybox does at start-up -- setlocale(LC_CTYPE, ""), then C.UTF-8 when
 * the codeset is not UTF-8 -- and what it relies on after: mbrtowc/wcrtomb
 * over UTF-8 (including a sequence split across calls and the invalid forms
 * glibc refuses), MB_CUR_MAX, nl_langinfo(CODESET), wcwidth, the isw*
 * classes and towupper/towlower. The classification and width tables are
 * checked whole: a hash over every code point 0..0x10FFFF, so one wrong
 * range anywhere changes a line. The C locale is checked before and after,
 * since everything there must stay exactly as it was.
 *
 * The program sets its own environment, so the answer does not depend on
 * the caller's LANG. Only the C, POSIX and C.UTF-8 names are probed: other
 * locales depend on what the host has installed. */
#define _GNU_SOURCE
#include <langinfo.h>
#include <locale.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <wctype.h>

static unsigned long hash_tables(void) {
  unsigned long h = 5381;
  wint_t c;
  for (c = 0; c <= 0x10FFFF; c++) {
    unsigned k = (iswalpha(c) ? 1 : 0) | (iswdigit(c) ? 2 : 0) | (iswblank(c) ? 4 : 0) |
                 (iswcntrl(c) ? 8 : 0) | (iswgraph(c) ? 16 : 0) | (iswprint(c) ? 32 : 0) |
                 (iswlower(c) ? 64 : 0) | (iswupper(c) ? 128 : 0) | (iswpunct(c) ? 256 : 0) |
                 (iswspace(c) ? 512 : 0) | (iswxdigit(c) ? 1024 : 0) | (iswalnum(c) ? 2048 : 0);
    h = h * 33 + k;
    h = h * 33 + (unsigned)(wcwidth((wchar_t)c) + 1);
    h = h * 33 + (unsigned)(towlower(c) - c);
    h = h * 33 + (unsigned)(towupper(c) - c);
    h &= 0xFFFFFFFFUL;
  }
  return h;
}

/* A second thread does not see the first one's uselocale. */
static const char *th_codeset;
static void *th_body(void *a) { (void)a; th_codeset = nl_langinfo(CODESET); return 0; }
static const char *other_thread_codeset(void) {
  pthread_t t;
  if (pthread_create(&t, 0, th_body, 0)) return "no thread";
  pthread_join(t, 0);
  return th_codeset;
}

static void dec(const char *what, const char *s, size_t n) {
  mbstate_t st;
  wchar_t wc = 0;
  size_t r;
  memset(&st, 0, sizeof st);
  r = mbrtowc(&wc, s, n, &st);
  printf("mbrtowc %-10s -> %ld U+%04X\n", what, (long)r, (unsigned)(r <= 6 ? wc : 0));
}

static void enc(wchar_t wc) {
  char b[8];
  mbstate_t st;
  size_t r, i;
  memset(&st, 0, sizeof st);
  memset(b, 0, sizeof b);
  r = wcrtomb(b, wc, &st);
  printf("wcrtomb U+%04X -> %ld", (unsigned)wc, (long)r);
  for (i = 0; r != (size_t)-1 && i < r; i++) printf(" %02X", (unsigned char)b[i]);
  printf("\n");
}

static void probe(void) {
  static const wchar_t ws[] = {'A', 0xE9, 0x301, 0x79C1, 0x3002, 0x1F600, 0xAD, 0x200B, 0x7F, 0};
  static const wint_t cs[] = {'a', 0xE9, 0xC9, 0x3B1, 0x391, 0x4E00, 0x2028, 0x3000, 0xA0, 0x1E9E, 0xDF, 0};
  const wchar_t *p;
  const wint_t *q;
  printf("MB_CUR_MAX %d CODESET %s\n", (int)MB_CUR_MAX, nl_langinfo(CODESET));
  for (p = ws; *p; p++) printf("wcwidth U+%04X %d\n", (unsigned)*p, wcwidth(*p));
  for (q = cs; *q; q++)
    printf("U+%04X alpha=%d lower=%d upper=%d space=%d print=%d punct=%d tl=%04X tu=%04X\n",
           (unsigned)*q, !!iswalpha(*q), !!iswlower(*q), !!iswupper(*q), !!iswspace(*q),
           !!iswprint(*q), !!iswpunct(*q), (unsigned)towlower(*q), (unsigned)towupper(*q));
  printf("btowc(0x41)=%d btowc(0xC3)=%d wctob(0xE9)=%d\n", (int)btowc(0x41), (int)btowc(0xC3),
         wctob(0xE9));
  printf("tables %08lx\n", hash_tables());
}

int main(void) {
  wchar_t wbuf[16];
  char buf[32];
  mbstate_t st;
  wchar_t wc;
  size_t r;
  int n;

  unsetenv("LC_ALL");
  unsetenv("LC_CTYPE");
  unsetenv("LANG");

  printf("== C\n");
  printf("query %s\n", setlocale(LC_ALL, 0));
  probe();
  dec("e-acute", "\xC3\xA9", 2);

  printf("== names\n");
  printf("empty -> %s\n", setlocale(LC_CTYPE, ""));
  printf("bogus -> %s\n", setlocale(LC_CTYPE, "xx_YY.NOPE") ? "set" : "(null)");
  printf("POSIX -> %s\n", setlocale(LC_ALL, "POSIX"));
  setenv("LANG", "C.UTF-8", 1);
  printf("LANG=C.UTF-8 empty -> %s\n", setlocale(LC_CTYPE, ""));
  printf("all query -> %s\n", setlocale(LC_ALL, 0));
  printf("numeric query -> %s\n", setlocale(LC_NUMERIC, 0));
  printf("C -> %s\n", setlocale(LC_ALL, "C"));
  printf("C.utf8 -> %s\n", setlocale(LC_CTYPE, "C.utf8"));
  printf("C.UTF-8 -> %s\n", setlocale(LC_ALL, "C.UTF-8"));
  printf("all query -> %s\n", setlocale(LC_ALL, 0));

  printf("== C.UTF-8\n");
  probe();
  dec("ascii", "A", 1);
  dec("e-acute", "\xC3\xA9", 2);
  dec("cjk", "\xE7\xA7\x81", 3);
  dec("emoji", "\xF0\x9F\x98\x80", 4);
  dec("max", "\xF4\x8F\xBF\xBF", 4);
  dec("past-max", "\xF4\x90\x80\x80", 4);
  dec("overlong", "\xC0\x80", 2);
  dec("overlong3", "\xE0\x80\xAF", 3);
  dec("surrogate", "\xED\xA0\x80", 3);
  dec("lone-cont", "\x80", 1);
  dec("bad-cont", "\xC3\x41", 2);
  dec("f5", "\xF5\x80\x80\x80", 4);
  dec("short", "\xE7\xA7", 2);
  dec("5byte", "\xF8\x88\x80\x80\x80", 5);
  dec("6byte", "\xFD\xBF\xBF\xBF\xBF\xBF", 6);
  dec("6overlong", "\xFC\x80\x80\x80\x80\x80", 6);
  dec("fe", "\xFE\x80", 2);
  dec("c0-alone", "\xC0", 1);
  dec("e0-80", "\xE0\x80", 2);
  dec("ed-a0", "\xED\xA0", 2);
  dec("f0-80", "\xF0\x80", 2);
  dec("f8-80", "\xF8\x80", 2);
  dec("nul", "", 1);

  /* a sequence split across three calls carries its state */
  memset(&st, 0, sizeof st);
  r = mbrtowc(&wc, "\xF0\x9F", 2, &st);
  printf("split1 %ld mbsinit=%d\n", (long)r, mbsinit(&st));
  r = mbrtowc(&wc, "\x98", 1, &st);
  printf("split2 %ld\n", (long)r);
  r = mbrtowc(&wc, "\x80" "Z", 2, &st);
  printf("split3 %ld U+%04X mbsinit=%d\n", (long)r, (unsigned)wc, mbsinit(&st));

  enc('A'); enc(0xE9); enc(0x79C1); enc(0x1F600); enc(0x10FFFF);
  enc(0xD800); enc(0x110000); enc(0x200000); enc(0x7FFFFFFF);
  printf("beyond: w=%d alpha=%d print=%d tu=%X w(-1)=%d alpha(WEOF)=%d tu(WEOF)=%d\n",
         wcwidth(0x110000), !!iswalpha(0x110000), !!iswprint(0x110000),
         (unsigned)towupper(0x110000), wcwidth(-1), !!iswalpha(WEOF), (int)towupper(WEOF));

  n = mbtowc(&wc, "\xE7\xA7\x81", 3);
  printf("mbtowc %d U+%04X\n", n, (unsigned)wc);
  printf("mbtowc short %d\n", mbtowc(&wc, "\xE7\xA7", 2));
  mbtowc(0, 0, 0);
  printf("mblen %d %d\n", mblen("\xF0\x9F\x98\x80", 4), mblen("\xC3", 1));
  n = wctomb(buf, 0x79C1);
  printf("wctomb %d %02X %02X %02X\n", n, (unsigned char)buf[0], (unsigned char)buf[1],
         (unsigned char)buf[2]);
  r = mbstowcs(wbuf, "a\xC3\xA9\xE7\xA7\x81", 16);
  printf("mbstowcs %ld %04X %04X %04X\n", (long)r, (unsigned)wbuf[0], (unsigned)wbuf[1],
         (unsigned)wbuf[2]);
  printf("mbstowcs bad %ld\n", (long)mbstowcs(wbuf, "a\xC3", 16));
  printf("mbstowcs count %ld\n", (long)mbstowcs(0, "\xE7\xA7\x81\xE7\xA7\x81", 0));
  r = wcstombs(buf, wbuf, sizeof buf);
  printf("wcstombs %ld %s\n", (long)r, r == 6 && !strcmp(buf, "a\xC3\xA9\xE7\xA7\x81") ? "ok" : "BAD");
  {
    /* an array, not L"\x79C1...": a wide literal's \x escape above 0xFF is
       its own bug (bug-c-a-wide-string-literal-truncates-hex-escapes-above-ff) */
    static const wchar_t w3[] = {0x79C1, 0x306F, 'a', 0};
    printf("wcswidth %d\n", wcswidth(w3, 3));
  }

  printf("== back to C\n");
  printf("C -> %s\n", setlocale(LC_ALL, "C"));
  probe();

  /* toybox's way: uselocale(newlocale(LC_CTYPE_MASK, "C.UTF-8", 0)), per
     thread, leaving the global locale C */
  printf("== uselocale\n");
  {
    locale_t u8 = newlocale(LC_CTYPE_MASK, "C.UTF-8", 0), prev;
    printf("newlocale bogus -> %s\n", newlocale(LC_CTYPE_MASK, "xx_YY.NOPE", 0) ? "set" : "(null)");
    printf("newlocale C.UTF-8 -> %s\n", u8 ? "ok" : "(null)");
    prev = uselocale(u8);
    printf("prev is global %d, query is u8 %d\n", prev == LC_GLOBAL_LOCALE, uselocale(0) == u8);
    printf("global still %s; CODESET %s MB_CUR_MAX %d wcwidth %d\n", setlocale(LC_ALL, 0),
           nl_langinfo(CODESET), (int)MB_CUR_MAX, wcwidth(0x79C1));
    printf("other thread: %s\n", other_thread_codeset());
    uselocale(LC_GLOBAL_LOCALE);
    printf("restored: CODESET %s wcwidth %d\n", nl_langinfo(CODESET), wcwidth(0x79C1));
    freelocale(u8);
  }
  return 0;
}
