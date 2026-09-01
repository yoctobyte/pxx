/* C99 6.10.1: a `#if` expression is evaluated in intmax_t/uintmax_t and the
   USUAL ARITHMETIC CONVERSIONS apply -- one unsigned operand makes the whole
   comparison unsigned. pxx's `#if` evaluator was purely signed Int64, so
   `ULONG_MAX > 0xffffffff' came out FALSE and busybox took the 32-bit arm of
   its byteswap header, emitting a call to bb_bswap_64 that gcc never emits.
   That undefined reference was the last failure of the 26-applet unity.

   Rows 4, 7 and 9 are the must-NOT-break rows -- they pass before and after,
   and they are the ones that say what the fix must leave alone:
     4  a wholly signed comparison stays signed;
     7  `>>' was already logical on Int64, so the signed arm is untouched;
     9  `==' needs no flag at all -- equality of bit patterns is the same
        question either way, which is why the equality level only CLEARS it.
   The other seven all print WRONG against the pre-fix compiler.
   feature-c-corpus-busybox-multi-applet */
#include <stdio.h>
#include <limits.h>

int main(void) {
#if ULONG_MAX > 0xffffffff
  printf("1 ok\n");
#else
  printf("1 WRONG\n");
#endif
#if 0xffffffffffffffffUL > 0
  printf("2 ok\n");
#else
  printf("2 WRONG\n");
#endif
#if 18446744073709551615UL > 1
  printf("3 ok\n");
#else
  printf("3 WRONG\n");
#endif
#if -1 < 0
  printf("4 ok\n");
#else
  printf("4 WRONG\n");
#endif
#if -1 > 0u
  printf("5 ok\n");
#else
  printf("5 WRONG\n");
#endif
#if (0xffffffffffffffffUL / 2) == 0x7fffffffffffffffUL
  printf("6 ok\n");
#else
  printf("6 WRONG\n");
#endif
#if (0xffffffffffffffffUL >> 4) == 0x0fffffffffffffffUL
  printf("7 ok\n");
#else
  printf("7 WRONG\n");
#endif
#if (1 ? 0xffffffffffffffffUL : 0) > 0
  printf("8 ok\n");
#else
  printf("8 WRONG\n");
#endif
#if (-1 == 0xffffffffffffffffUL)
  printf("9 ok\n");
#else
  printf("9 WRONG\n");
#endif
#if (2u - 3u) > 0
  printf("10 ok\n");
#else
  printf("10 WRONG\n");
#endif
  return 0;
}
