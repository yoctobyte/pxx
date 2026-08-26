/* C99 7.17: <stddef.h> defines wchar_t. It is the header most code reaches the
   type through — <wchar.h> is for the wide-string FUNCTIONS — and crtl had the
   typedef only in <wchar.h>. busybox's libbb.h includes <stddef.h> and never
   <wchar.h>, so libbb/lineedit.c died as `stray token at top level: 'wchar_t'`.

   C99 7.24.1 mbstate_t was missing entirely. Code that IMPLEMENTS the multibyte
   conversions — busybox defines its own wcrtomb/wcstombs — only needs the type,
   to name a parameter it then ignores. Without it the parameter list mis-parsed
   and the function body reached IR lowering as a bare integer literal ("could
   not lower AST node (kind 1)").

   The <wchar.h> include sits in the MIDDLE of this file on purpose: everything
   above it must compile with <stddef.h> alone, which is the claim under test.
   mbstate_t is deliberately NOT in <stddef.h> — gcc rejects it there too.

   Oracle: gcc -O0. sizeof(wchar_t) is 4 on every target pxx builds for. */
#include <stddef.h>

int printf(const char *, ...);

/* Compiled with <stddef.h> alone — the claim under test. */
static int wide_sum(const wchar_t *p, size_t n) {
  size_t i; int t = 0;
  for (i = 0; i < n; i++) t += (int)p[i];
  return t;
}

/* ---- everything below needs <wchar.h> ---- */
#include <wchar.h>

/* the busybox shape: implement a conversion, take the state and ignore it */
static size_t my_wcrtomb(char *s, wchar_t wc, mbstate_t *ps) {
  (void)ps;
  if (wc < 0x80) { *s = (char)wc; return 1; }
  s[0] = (char)(0xc0 | (wc >> 6));
  s[1] = (char)(0x80 | (wc & 0x3f));
  return 2;
}

int main(void) {
  wchar_t w = 'A';
  wchar_t ws[3];
  const wchar_t *p;
  char buf[4];
  size_t n;

  printf("%d %d\n", (int)w, (int)sizeof(wchar_t));

  /* signed, and wide enough for the whole BMP and beyond */
  w = -1;
  printf("%d %d\n", (int)w, (int)(sizeof(wchar_t) >= 2));

  /* usable as an array element and a pointer target */
  ws[0] = 'a'; ws[1] = 0x20ac; ws[2] = 0;
  p = ws;
  printf("%d %d %d\n", (int)p[0], (int)p[1], (int)p[2]);
  printf("%d\n", wide_sum(ws, 3));

  n = my_wcrtomb(buf, 'Z', 0);
  printf("%d %d\n", (int)n, buf[0]);
  n = my_wcrtomb(buf, 0xe9, 0);      /* U+00E9, two UTF-8 bytes */
  printf("%d %d %d\n", (int)n, (unsigned char)buf[0], (unsigned char)buf[1]);
  return 0;
}
