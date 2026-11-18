/* __int128 on x86-64 (rdx:rax, ir_codegen_i128.inc), against gcc's output.
   feature-c-int128-and-attribute-mode */
#include <stdio.h>
#include <stdint.h>
typedef unsigned __int128 u128;
typedef __int128 i128;
typedef unsigned long mp_word __attribute__((mode(TI)));
static void p(const char *n, u128 v){ printf("%s %016llx%016llx\n", n, (unsigned long long)(v >> 64), (unsigned long long)v); }
static u128 mul64(uint64_t a, uint64_t b) { return (u128)a * b; }
static i128 many(int a, int b, int c, i128 d, int e, i128 f, i128 g) { return d + f - g + a + b + c + e; }
static u128 sel(int c, u128 x, u128 y) { return c ? x : y; }
struct pair { u128 lo; uint64_t tag; };
static struct pair mk(u128 v) { struct pair r; r.lo = v; r.tag = 9; return r; }
static void bump(u128 *q) { *q += 1; (*q) <<= 3; q[1] = q[0] * 2; }
int main(void){
  uint64_t hi = 0xFFFFFFFFFFFFFFFFull;
  p("mul64", mul64(hi, hi));
  p("many", (u128)many(1, 2, 3, (i128)1 << 100, 4, -7, 3));
  p("sel", sel(1, (u128)5 << 70, 3)); p("sel0", sel(0, (u128)5 << 70, 3));
  u128 x = hi; x += 1; x *= 3; x <<= 2; x >>= 1; x |= 1; x ^= (u128)1 << 127; x &= ~(u128)2; x -= 4;
  p("x", x);
  u128 c = 0; c++; ++c; c--; p("c", c);
  i128 m = 0; m--; p("m", (u128)m); m = -m; p("m2", (u128)m);
  u128 arr[4] = {0}; arr[0] = hi; bump(arr); p("arr0", arr[0]); p("arr1", arr[1]);
  u128 *pp = arr; pp++; p("pp", *pp);
  struct pair s = mk((u128)hi << 32); p("pair", s.lo); printf("tag %llu\n", (unsigned long long)s.tag);
  mp_word r = (mp_word)hi * hi + hi; uint64_t digit = (uint64_t)(r & ((((mp_word)1) << 60) - 1)); uint64_t carry = (uint64_t)(r >> 60);
  printf("mp %llx %llx\n", (unsigned long long)digit, (unsigned long long)carry);
  i128 neg = -5; uint64_t u = (uint64_t)hi; u128 z = u; i128 zs = (int64_t)-3;
  p("neg", (u128)neg); p("z", z); p("zs", (u128)zs);
  printf("cmp %d %d %d\n", neg < z, (i128)neg < (i128)z, z > (u128)neg);
  int k = 0; for (u128 i = 0; i < 5; i++) k++; printf("k %d\n", k);
  printf("sz %d\n", (int)__SIZEOF_INT128__);
  return 0; }
