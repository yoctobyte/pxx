/* b200: C hex/octal integer-constant type ladder (C99 6.4.4.1). An unsuffixed
   hex constant that overflows int but fits unsigned int is UNSIGNED int, so
   `(int)-1 != 0xffffffff` is FALSE after usual arithmetic conversions
   (c-testsuite 00104). Decimal constants skip the unsigned rungs. */
#include <stdint.h>
int main(void) {
    int32_t x = 0;
    x = ~x;                              /* -1 as int32 */
    if (x != 0xffffffff) return 1;       /* unsigned int 4294967295 == -1 (mod 2^32) */
    int64_t l = 0;
    l = ~l;                              /* -1 as int64 */
    if (x != 0xffffffffffffffff) return 2;  /* unsigned long: int -1 -> 0xff..ff */
    /* decimal 4294967295 is `long` (signed 64), so != -1 stays true */
    if ((int32_t)-1 == 4294967295) return 3;
    /* octal ladder: 037777777777 (octal) = 0xffffffff = unsigned int */
    if (x != 037777777777) return 4;
    return 42;
}
