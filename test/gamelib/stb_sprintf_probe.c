/* stb probe (game-library ladder): stb_sprintf.h single-header, full impl.
   Proves the function-TYPE typedef callback idiom
   (typedef char *STBSP_SPRINTFCB(...); stbsp_vsprintfcb(CB *callback,...)) —
   the crux of bug-c-inline-fnptr-param-call — by driving stb's real callback
   engine end to end. Integer/hex/string/width/precision formatting is
   byte-exact vs gcc; stb's FLOAT engine has a separate gap
   (bug-c-stb-sprintf-float-empty), so this probe stays on the integer subset.
   Exit 42. */
#define STB_SPRINTF_IMPLEMENTATION
#include "stb_sprintf.h"

int strcmp(const char *, const char *);
int printf(const char *, ...);

int main(void) {
    char buf[128];
    stbsp_sprintf(buf, "%d|%5d|%-5d|%05d|%x|%X|%s|%c", -42, 7, 7, 7, 48879, 48879, "yo", 'Z');
    if (strcmp(buf, "-42|    7|7    |00007|beef|BEEF|yo|Z")) { printf("GOT [%s]\n", buf); return 1; }
    /* %n-free callback path: a long string forces stb to flush through its
       STBSP_SPRINTFCB callback (the fn-type-typedef mechanism under test). */
    stbsp_sprintf(buf, "%d.%d.%d.%d", 192, 168, 1, 42);
    if (strcmp(buf, "192.168.1.42")) { printf("GOT [%s]\n", buf); return 2; }
    /* float subset (bug-c-stb-sprintf-float-empty): stb's powten double tables
       are file-scope double arrays; the %f/%g engine needs them initialized. */
    stbsp_sprintf(buf, "%f|%.2f|%g|%e", 3.5, 42.25, 0.001, 12345.678);
    if (strcmp(buf, "3.500000|42.25|0.001|1.234568e+04")) { printf("GOT [%s]\n", buf); return 3; }
    return 42;
}
