/* Correctly-rounded crtl cbrt (b379, feature-crtl-libm-correctly-rounded-
   transcendentals): Newton in double + one double-double correction step.
   NOTE: runtime glibc cbrt is only ~1-ulp accurate and misrounds ~55% of
   random arguments — glibc cbrt(27.0) is 3.0000000000000004(!). These
   expected strings are CORRECT rounding (glibc's compile-time MPFR folding
   agrees; its runtime libm does not always). */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include <math.h>   /* the exp->__crtl_exp macro — plain `exp` binds to Pascal Exp */
static int ck(double v, const char *want, int code) {
    char b[64];
    snprintf(b, sizeof b, "%.17g", v);
    if (strcmp(b, want) != 0) { printf("FAIL %d got=%s want=%s\n", code, b, want); return code; }
    return 0;
}
int main(void) {
    int r;
    if ((r = ck(cbrt(27.0), "3", 1))) return r;      /* runtime glibc: ...04 */
    if ((r = ck(cbrt(-8.0), "-2", 2))) return r;
    if ((r = ck(cbrt(2.0), "1.2599210498948732", 3))) return r;
    if ((r = ck(cbrt(10.0), "2.1544346900318838", 4))) return r;
    if ((r = ck(cbrt(729.0), "9", 5))) return r;
    if ((r = ck(cbrt(1.7976931348623157e308), "5.6438030941223623e+102", 6))) return r;
    if ((r = ck(cbrt(1e-300), "1e-100", 7))) return r;
    if ((r = ck(cbrt(0.0), "0", 8))) return r;
    /* subnormal input via bits (the subnormal LITERAL parse bug is separate) */
    {
        unsigned long long b = 1ull;                 /* min subnormal */
        if ((r = ck(cbrt(*(double *)&b), "1.7031839360032603e-108", 9))) return r;
    }
    printf("ok\n");
    return 42;
}
