/* `--emit-obj --freestanding`: an object for code with no runtime under it
   (a kernel). Checked by its Makefile row with readelf, not by running it:
   - no .init_array and no .fini_array (nothing would run them);
   - no crtl implementation pulled in by the headers below (no strlen or
     strsignal body in the object; the program brings its own);
   - .bss under 4 KiB (no 32 KiB signal alternate stack);
   - its own functions exported, the libc names it calls left undefined;
   - va_arg works: stdarg is compiler support, so its __pxx_va_arg_* helpers
     ARE in the object (weak, one per object is fine), as gcc's builtin
     va_arg needs no library either. */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <string.h>

size_t strlen(const char *s);

uint64_t fs_sum(const uint8_t *p, size_t n)
{
    uint64_t s = 0;
    for (size_t i = 0; i < n; i++)
        s += p[i];
    return s + strlen((const char *)p);
}

long fs_vsum(int n, ...)
{
    va_list ap;
    long s = 0;
    va_start(ap, n);
    while (n-- > 0)
        s += va_arg(ap, long);
    va_end(ap);
    return s;
}
