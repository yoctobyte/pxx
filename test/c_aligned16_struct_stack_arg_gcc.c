/* The gcc -c half of c_aligned16_struct_stack_arg.c: callees pxx calls, and
 * callers that call pxx's. Included by the main file under -dA16_ONE_FILE
 * where there is no linker (aarch64). feature-c-int128-other-targets-float-and-narrow-modes */
#ifndef A16_ONE_FILE
struct W { __int128 v; };
struct B { long a; __int128 v; long c; };
struct __attribute__((aligned(16))) A { long a, b; };
#endif
long gw(long a, long b, long c, long d, long e, long f, long h, struct W w, long z) {
  return (long)w.v * 100 + (long)(w.v >> 64) * 10 + z + a + h;
}
long gw2(long a, long b, long c, long d, long e, long f, struct W w, long z) {
  return (long)w.v * 100 + (long)(w.v >> 64) * 10 + z + a + f;
}
long gb(long a, struct B s, long z) { return s.a * 1000 + (long)s.v * 100 + s.c * 10 + z + a; }
long ga(long a, long b, long c, long d, long e, long f, long h, struct A s, long z) {
  return s.a * 100 + s.b * 10 + z + h;
}
long pw(long, long, long, long, long, long, long, struct W, long);
long pb(long, struct B, long);
long pa(long, long, long, long, long, long, long, struct A, long);
long call_pxx(void) {
  struct W w; struct B s; struct A t;
  w.v = ((__int128)3 << 64) | 4;
  s.a = 1; s.v = 2; s.c = 3;
  t.a = 5; t.b = 6;
  return pw(1, 2, 3, 4, 5, 6, 7, w, 9) * 1000000 + pb(4, s, 5) * 1000 + pa(1, 2, 3, 4, 5, 6, 7, t, 8);
}
