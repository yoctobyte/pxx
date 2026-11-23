/* __int128 arguments and results by AAPCS64's placement: an even register
 * pair (x1 skipped after one long), x6:x7 after five longs, the stack at a
 * 16-byte boundary after seven (and the long after it does not drop back to
 * x7), five of them (four pairs, one on the stack), mixed with doubles, and
 * through function pointers. pxx's call sites were checked word by word
 * against clang --target=aarch64-linux-gnu; this file checks the callee reads
 * what the caller wrote, and runs on x86-64 too. Expected output from gcc.
 * feature-c-int128-other-targets-float-and-narrow-modes */
#include <stdio.h>
typedef __int128 i128;
typedef unsigned long long u64;
#define MK(h, l) (((i128)(h) << 64) | (u64)(l))
static u64 fold(i128 v) { return (u64)(v >> 64) * 1000003u + (u64)v; }
static long f1(long a, i128 b) { return a * 7 + (long)fold(b); }
static long f2(long a, long b, long c, long d, long e, i128 x, long z) {
  return a + b * 2 + c * 3 + d * 4 + e * 5 + (long)fold(x) * 6 + z * 7;
}
static long f3(long a, long b, long c, long d, long e, long f, long g, i128 x, long z) {
  return a + b + c + d + e + f + g * 11 + (long)fold(x) * 13 + z * 17;
}
static i128 f4(i128 a, i128 b, i128 c, i128 d, i128 e) {
  return a + b * 3 + c * 5 + d * 7 + e * 11;
}
static double f5(double p, i128 a, int k, double q, i128 b) {
  return p + q * k + (double)(a - b);
}
static i128 widen(int k) { return k; }
int main(void) {
  long (*p1)(long, i128) = f1;
  i128 (*p4)(i128, i128, i128, i128, i128) = f4;
  i128 r;
  printf("f1 %ld\n", f1(5, MK(2, 3)));
  printf("f2 %ld\n", f2(1, 2, 3, 4, 5, MK(6, 7), 8));
  printf("f3 %ld\n", f3(1, 2, 3, 4, 5, 6, 7, MK(8, 9), 10));
  r = f4(1, 2, 3, MK(-4, 4), MK(5, 6));
  printf("f4 %llu %llu\n", (u64)(r >> 64), (u64)r);
  printf("f5 %g\n", f5(0.5, MK(1, 0), 3, 2.25, 7));
  printf("p1 %ld\n", p1(-5, MK(-1, -2)));
  r = p4(widen(-1), 2, widen(3), 4, f4(1, 1, 1, 1, 1));
  printf("p4 %llu %llu\n", (u64)(r >> 64), (u64)r);
  printf("nested %ld\n", f3(1, 2, 3, 4, 5, 6, 7, f4(1, 2, 3, 4, 5), f1(1, 2)));
  return 0;
}
