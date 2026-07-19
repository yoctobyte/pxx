/* crtl rint family: round-to-nearest ties-to-EVEN (quickjs js_math needs
   lrint). Unity-links crtl (cjson-runner shape). Exit 42 = pass. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
int main(void) {
    if (rint(2.5) != 2.0) return 1;
    if (rint(3.5) != 4.0) return 2;
    if (rint(-2.5) != -2.0) return 3;
    if (rint(2.4) != 2.0) return 4;
    if (rint(2.6) != 3.0) return 5;
    if (lrint(7.5) != 8) return 6;
    if (lrint(6.5) != 6) return 7;
    if (nearbyint(-0.5) != -0.0) return 8;
    printf("ok\n");
    return 42;
}
