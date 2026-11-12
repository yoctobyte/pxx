/* `extern T name;` inside a function, with no file-scope declaration of name
   in this translation unit before it (Gibux fs/ext2.c: boot_epoch, defined
   in another file). Before 2026-11-12 the first use was "undeclared
   identifier". Here the definitions come later in the same file, so the
   program runs; the Makefile row also compiles it with -dNO_DEFINITIONS as an
   object and checks boot_epoch is an UND import. Output is gcc's. */
#include <stdio.h>
#include <stdint.h>

static uint64_t later(void)
{
    extern uint64_t boot_epoch;
    extern int counts[];
    return boot_epoch + (uint64_t)counts[2];
}

#ifndef NO_DEFINITIONS
uint64_t boot_epoch = 1700000000;
int counts[4] = { 1, 2, 3, 4 };

int main(void)
{
    boot_epoch += 5;
    printf("%llu\n", (unsigned long long)later());
    return 0;
}
#else
uint64_t use_it(void) { return later(); }
#endif
