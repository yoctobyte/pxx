/* `--emit-obj --freestanding`: an object for code with no runtime under it
   (a kernel). Checked by its Makefile row with readelf, not by running it:
   - no .init_array and no .fini_array (nothing would run them);
   - no crtl implementation pulled in by the headers below (no strlen or
     strsignal body in the object; the program brings its own);
   - .bss under 4 KiB (no 32 KiB signal alternate stack);
   - its own functions exported, the libc names it calls left undefined. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

size_t strlen(const char *s);

uint64_t fs_sum(const uint8_t *p, size_t n)
{
    uint64_t s = 0;
    for (size_t i = 0; i < n; i++)
        s += p[i];
    return s + strlen((const char *)p);
}
