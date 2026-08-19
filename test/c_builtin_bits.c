/* The gcc bit builtins cfront renames onto crtl helpers. The `l` row is the
   point: C `long` is machine-word-sized, so __builtin_clzl is the 64-bit
   helper on LP64 and the 32-bit one on ILP32 -- a hard-coded 64 would be
   wrong on i386/arm32/riscv32. ffs and parity are DEFINED at zero (gcc says
   0 for both), which is why they are not routed through ctz/popcount.
   Every number here is gcc's own answer on the same source.
   Found missing by a csmith --builtins sweep, feature-c-csmith-differential-fuzzing. */
#include <stdio.h>

int main(void)
{
  unsigned int a = 0x00F00000u;
  unsigned long b = 0x0000F00000000000UL;   /* top half only set on LP64 */
  unsigned long long c = 0x0000F00000000000ull;
  unsigned long sl = 0x80u;

  printf("%d %d %d\n", __builtin_clz(a), __builtin_ctz(a), __builtin_popcount(a));
  printf("%d %d %d\n", __builtin_clzll(c), __builtin_ctzll(c), __builtin_popcountll(c));
  /* the l row -- widths follow `long`, so these agree with gcc on every target */
  printf("%d %d %d\n", __builtin_clzl(sl), __builtin_ctzl(sl), __builtin_popcountl(sl));
  printf("%d %d\n", (int)(sizeof(unsigned long) * 8), __builtin_clzl(1UL));

  /* ffs: 1-based, and DEFINED at zero */
  printf("%d %d %d %d\n", __builtin_ffs(0), __builtin_ffs(1), __builtin_ffs(0x100),
         __builtin_ffsll(0ull));
  printf("%d %d\n", __builtin_ffsll(0x100000000ull), __builtin_ffsl(sl));

  /* parity: bit count mod 2, also defined at zero */
  printf("%d %d %d %d\n", __builtin_parity(0), __builtin_parity(7),
         __builtin_parityll(0xFFull), __builtin_parityl(sl));

  /* bswap */
  printf("%X %X %llX\n", (unsigned)__builtin_bswap16(0x1234u),
         __builtin_bswap32(0x11223344u),
         (unsigned long long)__builtin_bswap64(0x1122334455667788ull));
  (void)b;
  return 0;
}
