/* <wchar.h> / <wctype.h>: wcslen, the twelve isw* predicates, towlower/towupper.
 *
 * These were DECLARED by the headers and implemented nowhere, so calling one
 * imported it from glibc and the binary stopped being statically linked — the
 * same declared-but-unreachable shape as the socket veneer
 * (bug-cfront-spurious-dt-needed-libc-with-no-imports), and found in the same
 * sweep, because test/cwide_string_literal was importing wcslen.
 *
 * NO RECORDED EXPECTATIONS: the whole output is diffed against a gcc build of
 * this same file, so it cannot drift and no answer here was written by hand.
 *
 * WHY THE FULL RANGE. crtl is C-locale-only, and the interesting claim is not
 * "ASCII works" but "everything else is FALSE, and towlower/towupper are the
 * identity there" — which is exactly what glibc's C locale does. A test of a
 * few letters would pass against a wrong implementation that tried to be clever
 * above 127. So every value from WEOF(-1) through 255 is checked against all
 * twelve predicates, plus U+0100, U+0391 (Greek), U+4E00 (CJK) and U+1F600
 * (emoji) — values a locale-aware libc WOULD classify, and we must not.
 */
#include <wchar.h>
#include <wctype.h>
#include <stdio.h>

int main(void) {
  int c;
  unsigned i;
  int w[] = {0x100, 0x391, 0x4E00, 0x1F600};

  for (c = -1; c < 256; c++)
    printf("%d:%d%d%d%d%d%d%d%d%d%d%d%d:%d:%d\n", c,
      iswalnum(c)!=0, iswalpha(c)!=0, iswblank(c)!=0, iswcntrl(c)!=0,
      iswdigit(c)!=0, iswgraph(c)!=0, iswlower(c)!=0, iswprint(c)!=0,
      iswpunct(c)!=0, iswspace(c)!=0, iswupper(c)!=0, iswxdigit(c)!=0,
      (int)towlower(c), (int)towupper(c));

  for (i = 0; i < sizeof w / sizeof *w; i++)
    printf("w%d:%d%d%d:%d:%d\n", w[i], iswalpha(w[i])!=0, iswprint(w[i])!=0,
           iswspace(w[i])!=0, (int)towlower(w[i]), (int)towupper(w[i]));

  /* wcslen: empty, plain, and a string whose middle character is non-ASCII —
     wchar_t is 32-bit so that is one element, not a multi-byte sequence */
  printf("len=%d %d %d\n", (int)wcslen(L""), (int)wcslen(L"abc"), (int)wcslen(L"aéz"));

  /* wctype()/iswctype() must agree with the direct predicates. The tag VALUES
     are private to the implementation — C only promises a wctype() result is
     meaningful to iswctype() — so this compares behaviour, never the number. */
  printf("wct=%d%d%d%d\n",
         iswctype('a', wctype("alpha"))!=0, iswctype('1', wctype("digit"))!=0,
         iswctype(' ', wctype("space"))!=0, iswctype('a', wctype("digit"))!=0);
  printf("wct_unknown=%d\n", iswctype('a', wctype("nosuchclass"))!=0);

  return 0;
}
