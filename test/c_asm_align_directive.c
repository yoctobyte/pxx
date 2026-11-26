/* .p2align / .balign / .align inside a routine's inline asm: a loop-alignment
   hint (zstd's decompress loops, under gcc on x86-64). pxx reads and drops it;
   the routine must compile and compute the same as gcc's.
   bug-c-an-alignment-directive-in-inline-asm-refuses-the-routine */
#include <stdio.h>

static int sum(const int *a, int n)
{
    int s = 0, i;
    __asm__(".p2align 6");
    for (i = 0; i < n; i++) {
        s += a[i];
        __asm__(".p2align 4\n\t.balign 8, 0x90 # pad");
    }
    __asm__ __volatile__(".align 16; nop");
    __asm__(".p2align 5, , 31");
    return s;
}

int main(void)
{
    int a[6] = { 1, 2, 3, 4, 5, 6 };
    printf("asm align: %d\n", sum(a, 6));
    return 0;
}
