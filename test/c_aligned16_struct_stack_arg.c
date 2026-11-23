/* SysV puts an argument in memory whose alignment is 16 at a 16-byte aligned
 * slot: an __int128 (c_int128_stack_arg_alignment) and also a struct holding
 * one, or one declared aligned(16). pxx padded only the bare __int128, so a
 * struct { __int128 } after seven longs read 33166 where gcc reads 447. Linked
 * with c_aligned16_struct_stack_arg_gcc.c (gcc -c), both directions. On
 * aarch64, which has no linker here, pxx builds both halves as one file
 * (-dA16_ONE_FILE); the call shapes were checked against clang.
 * feature-c-int128-other-targets-float-and-narrow-modes */
#include <stdio.h>
struct W { __int128 v; };
struct B { long a; __int128 v; long c; };
struct __attribute__((aligned(16))) A { long a, b; };
long gw(long, long, long, long, long, long, long, struct W, long);
long gw2(long, long, long, long, long, long, struct W, long);
long gb(long, struct B, long);
long ga(long, long, long, long, long, long, long, struct A, long);
long call_pxx(void);
long pw(long a, long b, long c, long d, long e, long f, long h, struct W w, long z) {
  return (long)w.v * 100 + (long)(w.v >> 64) * 10 + z + a + h;
}
long pb(long a, struct B s, long z) { return s.a * 1000 + (long)s.v * 100 + s.c * 10 + z + a; }
long pa(long a, long b, long c, long d, long e, long f, long h, struct A s, long z) {
  return s.a * 100 + s.b * 10 + z + h;
}
int main(void) {
  struct W w; struct B s; struct A t;
  w.v = ((__int128)3 << 64) | 4;
  s.a = 1; s.v = 2; s.c = 3;
  t.a = 5; t.b = 6;
  printf("odd %ld\n", gw(1, 2, 3, 4, 5, 6, 7, w, 9));
  printf("even %ld\n", gw2(1, 2, 3, 4, 5, 6, w, 9));
  printf("big %ld\n", gb(4, s, 5));
  printf("aligned %ld\n", ga(1, 2, 3, 4, 5, 6, 7, t, 8));
  printf("gcc-calls-pxx %ld\n", call_pxx());
  return 0;
}
#ifdef A16_ONE_FILE
#include "c_aligned16_struct_stack_arg_gcc.c"
#endif
