/* __int128 on x86-64 (rdx:rax, ir_codegen_i128.inc), against gcc's output.
   feature-c-int128-and-attribute-mode */
#include <stdio.h>
#include <stdint.h>
typedef unsigned __int128 u128;
typedef __int128 i128;
static uint64_t st = 88172645463325252ull;
static uint64_t rnd(void){ st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; }
static u128 pick(void){
  uint64_t k = rnd() % 8; u128 v = ((u128)rnd() << 64) | rnd();
  switch (k) { case 0: return v >> (rnd() % 128); case 1: return (u128)(rnd() >> (rnd() % 64));
    case 2: return v; case 3: return ((u128)1 << (rnd() % 128)); case 4: return ((u128)1 << (rnd() % 128)) - 1;
    case 5: return (u128)rnd() << 64; default: return v >> 64; } }
int main(void){
  uint64_t h = 1469598103934665603ull, hs = h;
  for (int i = 0; i < 20000; i++) {
    u128 a = pick(), b = pick(); if (b == 0) b = 1;
    u128 q = a / b, r = a % b;
    h = (h ^ (uint64_t)q) * 1099511628211ull; h = (h ^ (uint64_t)(q >> 64)) * 1099511628211ull;
    h = (h ^ (uint64_t)r) * 1099511628211ull; h = (h ^ (uint64_t)(r >> 64)) * 1099511628211ull;
    i128 sa = (i128)a, sb = (i128)b; if (sb == -1 && sa == ((i128)1 << 127)) continue;
    i128 sq = sa / sb, sr = sa % sb;
    hs = (hs ^ (uint64_t)sq) * 1099511628211ull; hs = (hs ^ (uint64_t)((u128)sq >> 64)) * 1099511628211ull;
    hs = (hs ^ (uint64_t)sr) * 1099511628211ull; hs = (hs ^ (uint64_t)((u128)sr >> 64)) * 1099511628211ull;
  }
  printf("%016llx %016llx\n", (unsigned long long)h, (unsigned long long)hs);
  u128 w = ((u128)0x123456789abcdefull << 64) | 0xfedcba9876543210ull; uint64_t d = 1000000007ull;
  printf("%llx %llx %lld\n", (unsigned long long)(w / d), (unsigned long long)(w % d), (long long)((i128)-7 / 2 + (i128)-7 % 2 * 10));
  return 0; }
