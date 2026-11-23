/* A cast written with a built-in 128-bit spelling, `(__int128)5`, was
 * "unknown type name in cast": the undeclared-type check did not know the
 * spellings are built in. Against gcc. feature-c-int128-other-targets-float-and-narrow-modes */
#include <stdio.h>
typedef unsigned long long u64;
int main(void) {
  __int128 x = ((__int128)5 << 64) | 7;
  unsigned __int128 y = (unsigned __int128)-1;
  __int128_t z = (__int128_t)x * 3;
  __uint128_t w = (__uint128_t)(u64)-1 * 2;
  long n = (long)(x >> 64);
  printf("%llu %llu %llu %llu %llu %llu %ld\n", (u64)(x >> 64), (u64)x, (u64)(y >> 64), (u64)(z >> 64), (u64)(w >> 64), (u64)w, n);
  return 0;
}
