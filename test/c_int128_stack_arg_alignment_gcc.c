/* gcc's half of c_int128_stack_arg_alignment: compiled by gcc -c, linked with
 * the pxx object. Each function mixes its arguments into one number so any
 * misplaced eightbyte changes it. */
typedef __int128 i128;
static unsigned long long mix(i128 x) { return (unsigned long long)(x >> 64) * 1000003ULL + (unsigned long long)x; }
unsigned long long g_odd(long a, long b, long c, long d, long e, long f, long g, i128 x, long h)
{ return mix(x) * 7 + a + b + c + d + e + f + g * 11 + h * 13; }
unsigned long long g_even(long a, long b, long c, long d, long e, long f, i128 x, long h)
{ return mix(x) * 7 + a + b + c + d + e + f + h * 13; }
unsigned long long g_two(long a, long b, long c, long d, long e, long f, long g, i128 x, long h, i128 y)
{ return mix(x) * 7 + mix(y) * 5 + a + f + g * 11 + h * 13; }
unsigned long long g_split(long a, long b, long c, long d, long e, i128 x, long f)
{ return mix(x) * 7 + a + b + c + d + e + f * 17; }
extern unsigned long long p_odd(long, long, long, long, long, long, long, i128, long);
extern unsigned long long p_two(long, long, long, long, long, long, long, i128, long, i128);
extern unsigned long long p_split(long, long, long, long, long, i128, long);
unsigned long long g_calls(void) {
  i128 x = 5, y = 9;
  x = (x << 64) | 7; y = (y << 64) | 3;
  return p_odd(1, 2, 3, 4, 5, 6, 9, x, 3) + p_two(1, 2, 3, 4, 5, 6, 9, x, 3, y) * 3 + p_split(1, 2, 3, 4, 5, x, 6) * 5;
}
