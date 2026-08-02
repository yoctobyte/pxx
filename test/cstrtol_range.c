/* strtol family: overflow clamping, ERANGE, and base-0 octal
 * (feature-crtl-libc-gap-batch-2026-08 round 3).
 *
 * strtol/strtoul used to accumulate on their own and SILENTLY WRAP:
 *   strtol("99999999999999999999", 0, 10) -> 7766279631452241919
 * where C requires LONG_MAX with errno = ERANGE. strtoul was worse, casting
 * the SIGNED result so it inherited the wrap and could not reach the top half
 * of its own range. Base 0 also ignored a leading '0' (octal). The 64-bit
 * strtoll/strtoull already clamped but never set errno.
 *
 * The value assertions are written as TARGET-INDEPENDENT booleans (is_LONG_MAX
 * rather than a literal), because long is 64-bit on x86-64/aarch64 and 32-bit
 * on i386/arm32 — printing the numbers would need a different expectation per
 * target, and those booleans are exactly what a caller relies on. This is also
 * what caught limits.h defining LONG_MAX as the 64-bit value on every target:
 * the clamp could not fire on 32-bit because the bound was unreachable.
 *
 * Every strtol call is sequenced BEFORE the printf that reads its endptr —
 * argument evaluation order is unspecified, and writing it the obvious way
 * made gcc read an uninitialised pointer and segfault.
 */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>

int main(void) {
  char *end; long r; unsigned long u; const char *s;

  /* LONG_MAX and friends must match the actual width of long */
  printf("limits_consistent: %d %d %d\n",
         LONG_MAX == (long)((~0UL) >> 1),
         LONG_MIN == -(long)((~0UL) >> 1) - 1,
         ULONG_MAX == ~0UL);

  s = "  -42abc"; end = 0; r = strtol(s, &end, 10);
  printf("parse=%d end=[%s]\n", r == -42, end);

  s = "zz"; end = 0; errno = 0; r = strtol(s, &end, 10);
  printf("nodigits: zero=%d end_at_start=%d\n", r == 0, end == s);

  errno = 0; r = strtol("99999999999999999999", 0, 10);
  printf("overflow: clamped=%d erange=%d\n", r == LONG_MAX, errno == ERANGE);

  errno = 0; r = strtol("-99999999999999999999", 0, 10);
  printf("underflow: clamped=%d erange=%d\n", r == LONG_MIN, errno == ERANGE);

  errno = 0; u = strtoul("99999999999999999999999", 0, 10);
  printf("ul_overflow: clamped=%d erange=%d\n", u == ULONG_MAX, errno == ERANGE);

  /* a value that fits must NOT be clamped and must not set ERANGE */
  errno = 0; r = strtol("12345", 0, 10);
  printf("inrange: value=%d no_erange=%d\n", r == 12345, errno != ERANGE);

  /* base 0: 0x -> hex, leading 0 -> OCTAL, else decimal */
  printf("base0: hex=%d octal=%d dec=%d\n",
         strtol("0x10", 0, 0) == 16, strtol("010", 0, 0) == 8,
         strtol("10", 0, 0) == 10);
  printf("base16=%d\n", strtol("0x1f", 0, 16) == 31);

  /* the 64-bit pair sets ERANGE too */
  errno = 0; (void)strtoll("99999999999999999999999", 0, 10);
  printf("ll_erange=%d\n", errno == ERANGE);
  errno = 0; (void)strtoull("99999999999999999999999", 0, 10);
  printf("ull_erange=%d\n", errno == ERANGE);

  return 0;
}
