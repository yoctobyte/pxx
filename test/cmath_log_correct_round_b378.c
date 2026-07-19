/* Correctly-rounded crtl log (b378, feature-crtl-libm-correctly-rounded-
   transcendentals): replaces the Pascal Ln bridge (1-ulp tails, e.g. the
   quickjs Math.log(10) oracle diff) with a double-double atanh-series
   kernel. Expected strings are correct rounding, verified against 80-digit
   decimal references and gcc compile-time folding (runtime glibc misrounds
   ~1e-4 of random args — vectors here are unambiguous ones). */
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
    if ((r = ck(log(1.0), "0", 1))) return r;
    if ((r = ck(log(10.0), "2.3025850929940459", 2))) return r;
    if ((r = ck(log(2.0), "0.69314718055994529", 3))) return r;
    if ((r = ck(log(2.718281828459045), "1", 4))) return r;
    if ((r = ck(log(1.5), "0.40546510810816438", 5))) return r;
    /* near 1: catastrophic-cancellation region */
    if ((r = ck(log(1.0000000000000002), "2.2204460492503128e-16", 6))) return r;
    /* range extremes (normal); min-normal exercises the e*ln2 path */
    if ((r = ck(log(1.7976931348623157e308), "709.78271289338397", 7))) return r;
    if ((r = ck(log(2.2250738585072014e-308), "-708.39641853226408", 8))) return r;
    /* specials */
    if ((r = ck(log(0.0), "-inf", 9))) return r;
    if ((r = ck(log(-1.0), "-nan", 10))) return r;
    printf("ok\n");
    return 42;
}
