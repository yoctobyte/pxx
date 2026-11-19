/* -fstack-protector-strong -mstack-protector-guard=global, end to end.
   fill() has a local array and is protected; an overflow of it must end in
   __stack_chk_fail (here: print and exit 42) instead of returning through a
   clobbered frame. __SSP_STRONG__ must be gcc's value, 3.
   feature-c-stack-protector-strong-global-guard */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

unsigned long __stack_chk_guard = 0x5a5a1234deadbeefUL;

void __stack_chk_fail(void)
{
    printf("stack smashed\n");
    fflush(stdout);
    exit(42);
}

static volatile int len;

int fill(void)
{
    char buf[16];
    memset(buf, 'A', (size_t)len);
    return buf[0];
}

int plain(int a, int b)
{
    return a * b + 1;
}

int main(void)
{
#ifdef __SSP_STRONG__
    printf("ssp %d\n", __SSP_STRONG__);
#endif
    len = 16;
    printf("in bounds %d %d\n", fill(), plain(6, 7));
    len = 64;
    printf("overflow %d\n", fill());
    return 0;
}
