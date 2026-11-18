/* __attribute__((weak)) on DATA: an extern nothing defines is a WEAK undefined
   symbol (address 0 after the link), at file scope and at block scope -- NetBSD
   tests `__stop_link_set_*` that way -- and a weak definition is WEAK.
   pxx wrote both as GLOBAL, so the first link failed with an undefined symbol.
   bug-c-a-weak-extern-object-is-a-strong-undefined-symbol */
#include <stdio.h>
extern int maybe_v __attribute__((weak));
int wv __attribute__((weak)) = 4;
static int blockref(void)
{
    extern int *const __stop_maybe[] __attribute__((__weak__));
    return __stop_maybe == 0;
}
int main(void) { printf("%d %d %d\n", &maybe_v == 0, blockref(), wv); return 0; }
