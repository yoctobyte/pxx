/* The xtensa heap on a no-MMU kernel: small allocations share 64 KiB arenas,
   a request over half an arena gets its own mapping, and freed big blocks are
   reused. tools/check_xtensa_heap_arenas.py reads the mappings from qemu -strace.
   feature-xtensa-heap-grows-in-small-arenas-on-no-mmu */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void)
{
    char *small[200], *big[6];
    int i; long sum = 0;
    for (i = 0; i < 200; i++) { small[i] = malloc(100 + i); memset(small[i], i & 0x7f, 100 + i); }
    for (i = 0; i < 6; i++) { big[i] = malloc(200000 + i * 1000); memset(big[i], 1, 200000 + i * 1000); }
    for (i = 0; i < 200; i++) sum += small[i][99];
    for (i = 0; i < 6; i++) { sum += big[i][199999]; free(big[i]); }
    for (i = 0; i < 3; i++) { big[i] = malloc(150000); memset(big[i], 2, 150000); sum += big[i][149999]; }
    printf("sum %ld\n", sum);
    return 0;
}
