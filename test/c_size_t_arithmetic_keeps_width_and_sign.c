/* SIZE_T ARITHMETIC KEEPS ITS WIDTH AND ITS SIGNEDNESS, ON EVERY TARGET.
 *
 * `sizeof` produced the native unsigned kind, which was right in width on
 * x86-64 and wrong in the conversions: on the ILP32 targets (i386, arm32,
 * riscv32) `-1 < sizeof(int)` answered 1 and `i / sizeof(int)` divided
 * signed; on the LP64 ones (x86-64, aarch64) `sizeof(a) - sizeof(b)` wrapped
 * at 2^32 (4294967292) where gcc wraps at 2^64.
 * bug-c-size-t-arithmetic-loses-its-width-or-its-signedness
 *
 * Every row is a C-guaranteed truth written in SIZE_MAX, so it prints the
 * same on every data model: one .expected file serves native and all four
 * cross targets, and native is also diffed against gcc.
 */
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>

#define R(e) printf("%s = %d\n", #e, (int)(e))

int main(void) {
  volatile int i = -8, j = -7, one = 1;
  volatile unsigned u = 1;
  int a4; double b8;
  R(-1 < sizeof(int));
  R(sizeof(int) - sizeof(double) == SIZE_MAX - 3);
  R(sizeof a4 - sizeof b8 > 0);
  R(sizeof(char) - 2 == SIZE_MAX);
  R(i / sizeof(int) == (SIZE_MAX >> 2) - 1);
  R(j % sizeof(int) == 1);
  R(-sizeof(int) > 0);
  R(-sizeof(int) == SIZE_MAX - 3);
  R(((sizeof(int) - 5) >> (sizeof(size_t) * 8 - 1)) == 1);
  R(u - sizeof(int) > 0);
  R(sizeof(int) * -one == (size_t)-4);
  R((sizeof(int) - 8) / 2 == SIZE_MAX / 2 - 1);
  R(sizeof(int) - sizeof(double) + 8 == 4);
  R(sizeof(sizeof(int)) == sizeof(size_t));
  R(sizeof(sizeof(int)) == sizeof(void *));
  /* long long against size_t: signed only where long long is the wider */
  R((-1LL < sizeof(int)) == (sizeof(size_t) < sizeof(long long)));
  return 0;
}
