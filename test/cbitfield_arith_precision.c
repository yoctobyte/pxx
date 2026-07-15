/* Regression: gcc reduces arithmetic on a >32-bit bitfield to the field's EXACT
   bit-precision (width), not to 64-bit. `+ - * <<` wrap mod 2^width (sign-extend
   if signed); pre-inc/dec yields the wrapped new value. cfront masks the result of
   each such op to the field width (bug-c-long-long-bitfield-promotion, the
   arithmetic-precision residual after the storage/read fix in 307128d5). Output
   pinned byte-identical to a gcc-built run. */
extern int printf(const char *, ...);

struct U {
  unsigned long long a : 33;
  unsigned long long b : 40;
  unsigned long long c : 41;
};

struct S {
  signed long long p : 40;
  signed long long q : 40;
};

struct U u = { 0x100000, 0x100000, 0x100000 };       /* each = 2^20 */
struct U w = { 0x1FFFFFFFFULL, 0xFFFFFFFFFFULL, 0 };  /* a,b saturated */
struct S s = { -3, 0x8000000000LL /* wraps to a negative :40 */ };

int main(void) {
  /* multiply reduces to the wider operand precision */
  printf("mul33=%llu mul40=%llu mul41=%llu\n",
         u.a * u.a,            /* 2^40 mod 2^33 = 0 */
         u.a * u.b,            /* 2^40 mod 2^40 = 0 */
         u.a * u.c);           /* 2^40 mod 2^41 = 2^40 */

  /* signed field arithmetic wraps two's-complement in the field width */
  printf("s.q=%lld sadd=%lld\n",
         (long long)s.q,       /* 0x8000000000 as signed :40 = -0x8000000000 */
         (long long)(s.p + s.p));  /* -6, stays signed */

  /* pre-inc/dec yield the wrapped NEW value; post yields the OLD value */
  printf("pre=%llu predec=%llu post=%llu\n",
         ++w.a,                /* (2^33-1)+1 = 0 */
         --w.b,                /* 0xFFFFFFFFFF stays (no wrap) */
         w.c--);               /* old value 0 */
  return 0;
}
