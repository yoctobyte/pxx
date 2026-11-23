/* SysV puts an __int128 passed in memory at a 16-byte aligned slot; pxx put it
 * in the next eightbyte, so pxx and gcc disagreed in both directions whenever
 * one went to the stack at an odd position. Linked with
 * c_int128_stack_arg_alignment_gcc.c (gcc -c); direct and indirect calls both
 * ways. feature-c-int128-other-targets-float-and-narrow-modes */
#include <stdio.h>
typedef __int128 i128;
static unsigned long long mix(i128 x) { return (unsigned long long)(x >> 64) * 1000003ULL + (unsigned long long)x; }
extern unsigned long long g_odd(long, long, long, long, long, long, long, i128, long);
extern unsigned long long g_even(long, long, long, long, long, long, i128, long);
extern unsigned long long g_two(long, long, long, long, long, long, long, i128, long, i128);
extern unsigned long long g_split(long, long, long, long, long, i128, long);
extern unsigned long long g_calls(void);
unsigned long long p_odd(long a, long b, long c, long d, long e, long f, long g, i128 x, long h)
{ return mix(x) * 7 + a + b + c + d + e + f + g * 11 + h * 13; }
unsigned long long p_two(long a, long b, long c, long d, long e, long f, long g, i128 x, long h, i128 y)
{ return mix(x) * 7 + mix(y) * 5 + a + f + g * 11 + h * 13; }
unsigned long long p_split(long a, long b, long c, long d, long e, i128 x, long f)
{ return mix(x) * 7 + a + b + c + d + e + f * 17; }
int main(void) {
  i128 x = 5, y = 9;
  unsigned long long (*fo)(long, long, long, long, long, long, long, i128, long) = g_odd;
  unsigned long long (*ft)(long, long, long, long, long, long, long, i128, long, i128) = g_two;
  unsigned long long r;
  x = (x << 64) | 7; y = (y << 64) | 3;
  r = g_odd(1, 2, 3, 4, 5, 6, 9, x, 3);
  printf("odd %llu\n", r);
  r = g_even(1, 2, 3, 4, 5, 6, x, 3);
  printf("even %llu\n", r);
  r = g_two(1, 2, 3, 4, 5, 6, 9, x, 3, y);
  printf("two %llu\n", r);
  r = g_split(1, 2, 3, 4, 5, x, 6);
  printf("split %llu\n", r);
  r = fo(1, 2, 3, 4, 5, 6, 9, x, 3);
  printf("ind-odd %llu\n", r);
  r = ft(1, 2, 3, 4, 5, 6, 9, x, 3, y);
  printf("ind-two %llu\n", r);
  r = g_calls();
  printf("gcc-calls-pxx %llu\n", r);
  return 0;
}
