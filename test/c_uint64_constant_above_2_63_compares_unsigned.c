/* An unsigned 64-bit constant at or above 2^63 holds its BIT PATTERN in the
   IR: 18446744073709551613UL is -3 there. The riscv32 and Xtensa backends
   narrow a compare to 32 bits when both sides "fit", and the constant arm
   tested the signed range of that pattern, so `18446744073709551613UL < 0`
   compared -3 < 0 and was TRUE (csmith seed 1130101, riscv32).
   Expectations are gcc -m32's.
   bug-r-a-uint64-constant-above-2-63-narrows-to-a-negative-32-bit-compare */
#include <stdio.h>
int main(void) {
  volatile int n = 5;
  volatile unsigned u = 5;
  printf("1 %d %d %d %d\n", 18446744073709551613UL < 0, 18446744073709551613UL > 5,
         18446744073709551613ULL == 0xFFFFFFFDu, 18446744073709551613ULL != -3);
  printf("2 %d %d %d %d\n", 9223372036854775808ULL <= 1, 9223372036854775808ULL >= 2,
         0 < 18446744073709551615ULL, 7 > 18446744073709551615ULL);
  printf("3 %d %d %d %d\n", 18446744073709551613UL < n, 18446744073709551613UL > n,
         n < 18446744073709551615ULL, u >= 18446744073709551615ULL);
  printf("4 %d %d\n", 18446744071562067968ULL < 0x80000000u, 18446744071562067968ULL == -2147483648LL);
  return 0;
}
