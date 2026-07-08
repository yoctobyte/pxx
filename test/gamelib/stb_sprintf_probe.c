/* stb probe (game-library ladder): stb_sprintf.h single-header, full impl.
   Deterministic: format a battery, byte-compare, exit 42 on match. */
#define STB_SPRINTF_IMPLEMENTATION
#include "stb_sprintf.h"

int strcmp(const char *, const char *);
int printf(const char *, ...);

int main(void) {
    char buf[128];
    stbsp_sprintf(buf, "%d|%5.2f|%s|%x|%08d", -42, 3.14159, "yo", 48879, 77);
    if (strcmp(buf, "-42| 3.14|yo|beef|00000077")) { printf("GOT %s\n", buf); return 1; }
    stbsp_sprintf(buf, "%g", 0.0625);
    if (strcmp(buf, "0.0625")) { printf("GOT %s\n", buf); return 2; }
    return 42;
}
