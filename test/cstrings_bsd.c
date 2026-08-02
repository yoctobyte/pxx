/* <strings.h> — the BSD string surface. The header did not exist, so
 * `#include <strings.h>` silently resolved from the HOST's /usr/include, making
 * the build depend on the box's libc and opening the ABI/macro mismatch the
 * compiler warns about (it names M_SQRT2 as the example, which was a real
 * silent-value bug in the same build — see cmath_constants.c).
 *
 * Expectations are gcc's output on this same file. Verified identical on
 * x86-64, i386, aarch64 and arm32. Exit code identifies the failing check. */
#include <strings.h>
#include <string.h>

int main(void) {
  char a[8] = "abcdefg", b[8] = "abcXXXX", z[8] = "12345678";

  /* bcmp: zero when the first n bytes match, nonzero otherwise */
  if (bcmp(a, b, 3) != 0) return 1;
  if (bcmp(a, b, 7) == 0) return 2;

  /* bcopy takes SOURCE first — the historical BSD order, reversed vs memmove */
  bcopy("HI", z, 2);
  if (z[0] != 'H' || z[1] != 'I' || z[2] != '3') return 3;

  bzero(z + 3, 2);
  if (z[3] != 0 || z[4] != 0) return 4;

  if (strcmp(index(a, 'c'), "cdefg") != 0) return 5;
  if (strcmp(rindex(a, 'g'), "g") != 0) return 6;

  /* ffs: 1-based position of the least significant set bit, 0 for 0 */
  if (ffs(0) != 0) return 7;
  if (ffs(1) != 1) return 8;
  if (ffs(8) != 4) return 9;
  if (ffs(1024) != 11) return 10;

  if (strcasecmp("AbC", "abc") != 0) return 11;
  if (strcasecmp("abd", "abc") <= 0) return 12;
  if (strncasecmp("ABCzzz", "abcqqq", 3) != 0) return 13;
  if (strncasecmp("ABCzzz", "abdqqq", 3) == 0) return 14;

  return 0;
}
