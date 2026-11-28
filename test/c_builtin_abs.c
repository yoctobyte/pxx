/* SPDX-License-Identifier: Zlib */
/* __builtin_abs/labs/llabs/imaxabs with NO header (systemd ABS()), and the
   injected prototypes agreeing with a later <stdlib.h>/<inttypes.h> (row
   c_babs26/hdr, built with -DWITH_HEADERS). Against gcc. feature-c-builtin-abs-family */
#ifdef WITH_HEADERS
#include <stdlib.h>
#include <inttypes.h>
#endif
int printf(const char *, ...);
int main(void)
{
    volatile long long big = -5000000000LL;
    volatile int i = -2147483647;
    printf("%lld %lld %ld %d\n", (long long)__builtin_imaxabs(big), __builtin_llabs(big + 1),
           __builtin_labs(-3L), __builtin_abs(i));
    printf("%d %lld\n", __builtin_abs(0), __builtin_llabs(-1LL));
    return 0;
}
