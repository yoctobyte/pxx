/* Correctly-rounded crtl exp (b377, feature-crtl-libm-correctly-rounded-
   transcendentals). Two prior failure shapes:
   1. Defining a C `exp` next to Pascal Exp broke the call binding (the
      argument never arrived — exp returned e^<stale xmm0>); crtl now routes
      exp through the __crtl_exp macro in math.h.
   2. The subnormal-result path double-rounded (53-bit round-to-odd has no
      margin in the top subnormal binade): exp(-708.9142446693706) came out
      one subnormal-ulp low.
   Expected strings are correct rounding, verified against 80-digit decimal
   references AND gcc's compile-time (MPFR) folding. NOTE: RUNTIME glibc
   misrounds ~6e-4 of random args (its documented 0.502-ulp bound), so a
   runtime-glibc differential may legally differ on hard cases — these
   vectors are ones where correct rounding is unambiguous. */
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
    unsigned long long bh = 0xc07cb27281f0264aull;   /* hard-rounding case */
    unsigned long long bs = 0xc08627505f825beaull;   /* subnormal result */
    int r;
    if ((r = ck(exp(0.0), "1", 1))) return r;
    if ((r = ck(exp(1.0), "2.7182818284590451", 2))) return r;
    if ((r = ck(exp(-1.0), "0.36787944117144233", 3))) return r;
    if ((r = ck(exp(0.6931471805599453), "2", 4))) return r;
    if ((r = ck(exp(*(double *)&bh), "3.9120543645533249e-200", 5))) return r;
    if ((r = ck(exp(*(double *)&bs), "1.3257309567460185e-308", 6))) return r;
    if ((r = ck(exp(709.782712893384), "1.7976931348622732e+308", 7))) return r;
    if ((r = ck(exp(710.0), "inf", 8))) return r;
    if ((r = ck(exp(-746.0), "0", 9))) return r;
    /* argument-binding shape: value flows through a variable and a loop */
    {
        double a[3]; int i; double s = 0.0;
        a[0] = -1.0; a[1] = 2.0; a[2] = 0.5;
        for (i = 0; i < 3; i++) s += exp(a[i]);
        if ((r = ck(s, "9.4056568108022205", 10))) return r;
    }
    printf("ok\n");
    return 42;
}
