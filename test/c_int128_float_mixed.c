/* __int128 meeting a floating value: arithmetic and compares, compound
 * assignment, struct fields and array elements, a double parameter, and an
 * __int128 return taking a double. Against gcc.
 * feature-c-int128-other-targets-float-and-narrow-modes */
#include <stdio.h>
static int part1(void) {
  __int128 x = 3, n = -5; unsigned __int128 u = ~(unsigned __int128)0; double d = 0.5, r1, r2, r3, r4; float f = 2.0f;
  x <<= 70;
  r1 = d * x; r2 = x + d; r3 = x / f; r4 = u - 1.0;
  printf("%g %g %g %g %d %d %d %d\n", r1, r2, r3, r4, x > d, d < x, n < 0.0, u == 3.4028236692093846e38);
  printf("%g %g\n", n * 1.5, 1.5 * u);
  return 0;
}
typedef unsigned long long u64;
static double half(double v) { return v / 2; }
static __int128 twice(__int128 v) { return v * 2; }
struct S { __int128 a; double b; };
int main(void) {
  part1();
  __int128 x = 1; struct S s; double arr[2];
  x <<= 80; x += 1.5; x *= 0.25;
  s.a = 7; s.b = s.a; s.a = s.b * 3e20;
  arr[1] = x;
  printf("%llu %llu %g %g %llu %llu %g\n", (u64)(x >> 64), (u64)x, half(x), s.b, (u64)(s.a >> 64), (u64)twice(2.5e10), arr[1]);
  return 0;
}
