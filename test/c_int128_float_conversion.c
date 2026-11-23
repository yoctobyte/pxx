/* __int128 <-> double and float, both signednesses, against gcc (its
 * __floattidf / __fixdfti family): correctly rounded to floating, truncated
 * toward zero from it. Edges at 2^63, 2^64, 2^127, ties, and a pseudo-random
 * sweep summarised as a checksum. feature-c-int128-other-targets-float-and-narrow-modes */
#include <stdio.h>
#include <string.h>
typedef __int128 i128;
typedef unsigned __int128 u128;
typedef unsigned long long u64;
static u64 bits(double d) { u64 b; memcpy(&b, &d, 8); return b; }
static unsigned fbits(float f) { unsigned b; memcpy(&b, &f, 4); return b; }
static u64 seed = 88172645463325252ULL;
static u64 rnd(void) { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed; }
static void pr(const char *tag, u128 v) { printf("%s %016llx%016llx\n", tag, (u64)(v >> 64), (u64)v); }
int main(void) {
  i128 s; u128 u; double d; float f;
  int i;
  u64 ck = 0;
  /* to floating */
  s = 1; s <<= 63; d = (double)s; printf("2^63 %016llx\n", bits(d));
  u = 1; u <<= 127; d = (double)u; printf("u2^127 %016llx\n", bits(d));
  s = 1; s <<= 127; d = (double)s; printf("-2^127 %016llx\n", bits(d));
  u = ~(u128)0; d = u; f = u; printf("umax %016llx %08x\n", bits(d), fbits(f));
  s = -1; d = s; printf("-1 %016llx\n", bits(d));
  u = 1; u = (u << 64) | 0x400ULL; d = u; printf("tie-even %016llx\n", bits(d));
  u = 1; u = (u << 64) | 0x800ULL; d = u; printf("tie-odd %016llx\n", bits(d));
  u = 1; u = (u << 64) | 0x801ULL; d = u; printf("above-tie %016llx\n", bits(d));
  u = 0x8000000000000001ULL; d = u; printf("2^63+1 %016llx\n", bits(d));
  u = 3; u = (u << 64) | 1; f = u; printf("float %08x\n", fbits(f));
  /* from floating */
  d = 1.5e30; s = d; pr("1.5e30", s);
  d = -1.5e30; s = d; pr("-1.5e30", s);
  d = 9.3e18; u = d; pr("9.3e18", u);
  d = 3.0e38; u = d; pr("3e38", u);
  d = -2.75; s = d; pr("-2.75", s);
  f = 1.0e25f; s = f; pr("f1e25", s);
  f = -7.5f; s = f; pr("f-7.5", s);
  for (i = 0; i < 2000; i++) {
    u64 hi = rnd() >> (rnd() & 63), lo = rnd();
    u = ((u128)hi << 64) | lo;
    s = (i128)u;
    d = u; ck = ck * 31 + bits(d);
    d = s; ck = ck * 31 + bits(d);
    f = u; ck = ck * 31 + fbits(f);
    f = s; ck = ck * 31 + fbits(f);
  }
  printf("to-float sweep %016llx\n", ck);
  ck = 0;
  for (i = 0; i < 2000; i++) {
    u64 b = (rnd() & 0x800FFFFFFFFFFFFFULL) | ((u64)(1023 + (rnd() % 126)) << 52);
    memcpy(&d, &b, 8);
    s = d; ck = ck * 31 + (u64)s + (u64)(s >> 64);
    if (d >= 0) { u = d; ck = ck * 31 + (u64)u + (u64)(u >> 64); }
  }
  printf("from-float sweep %016llx\n", ck);
  return 0;
}
