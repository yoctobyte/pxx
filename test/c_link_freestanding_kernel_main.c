/* The C half of tools/check_link_freestanding.sh: what a kernel's C looks
   like to the linker. An initialised pointer is .data with an R_X86_64_64
   (static data under --freestanding), a function is .text, and a large .bss
   array sits between .data and _end. Compiled with --emit-obj --freestanding.
   ksum is variadic, like a kernel's printf: under --freestanding its prologue
   must not spill the XMM argument registers (user FPU state lives there; gcc's
   -mgeneral-regs-only), and the check greps the image for any SSE/x87 at all. */
#include <stdarg.h>

static const char banner[] = "kernel";
const char *kbanner = banner;
unsigned long big_bss[512];

static long ksum(int n, ...)
{
    va_list ap;
    long s = 0;
    va_start(ap, n);
    while (n-- > 0)
        s += va_arg(ap, long);
    va_end(ap);
    return s;
}

long kmain(long magic)
{
    big_bss[3] = (unsigned long)magic;
    return (long)kbanner[0] + (long)big_bss[3] + ksum(3, 1L, 2L, 3L);
}
