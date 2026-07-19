/* Correctly-rounded crtl pow + full C99 special-case set (b380,
   feature-crtl-libm-correctly-rounded-transcendentals): dedicated
   double-double y*log(x) -> exp path replaces the old Exp(e*Ln(b)) bridge
   (which lost ~2 ulp and mishandled every special). Expected strings are
   correct rounding, verified against 120-digit decimal references and gcc
   compile-time folding. */
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
    double inf = 1.0 / 0.0, nan0 = 0.0 / 0.0, nz;
    unsigned long long nzb = 0x8000000000000000ull;
    int r;
    nz = *(double *)&nzb;
    if ((r = ck(pow(2.0, 0.5), "1.4142135623730951", 1))) return r;
    if ((r = ck(pow(10.0, 3.0), "1000", 2))) return r;
    if ((r = ck(pow(3.141592653589793, 2.718281828459045), "22.459157718361041", 3))) return r;
    if ((r = ck(pow(-2.0, 3.0), "-8", 4))) return r;
    if ((r = ck(pow(-2.0, 4.0), "16", 5))) return r;
    if ((r = ck(pow(1.0000000000000002, 4.5e15), "2.7161100340870359", 6))) return r;
    /* exact subnormal powers of two */
    if ((r = ck(pow(2.0, -1074.0), "4.9406564584124654e-324", 7))) return r;
    if ((r = ck(pow(10.0, -323.0), "9.8813129168249309e-324", 8))) return r;
    /* C99 F.9.4.4 specials */
    if ((r = ck(pow(0.0, 0.0), "1", 9))) return r;
    if ((r = ck(pow(nan0, 0.0), "1", 10))) return r;
    if ((r = ck(pow(1.0, nan0), "1", 11))) return r;
    if ((r = ck(pow(-2.0, 3.5), "-nan", 12))) return r;   /* domain error NaN */
    if ((r = ck(pow(0.0, -3.0), "inf", 13))) return r;
    if ((r = ck(pow(nz, -3.0), "-inf", 14))) return r;
    if ((r = ck(pow(nz, 3.0), "-0", 15))) return r;
    if ((r = ck(pow(-1.0, inf), "1", 16))) return r;
    if ((r = ck(pow(0.5, -inf), "inf", 17))) return r;
    if ((r = ck(pow(-inf, 3.0), "-inf", 18))) return r;
    if ((r = ck(pow(-inf, -3.0), "-0", 19))) return r;
    if ((r = ck(pow(2.0, 1024.0), "inf", 20))) return r;
    if ((r = ck(pow(2.0, -1075.0), "0", 21))) return r;
    printf("ok\n");
    return 42;
}
