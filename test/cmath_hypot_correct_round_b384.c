/* Correctly-rounded crtl hypot (b384): scale by the larger exponent, exact
   squared dds, dd sqrt, single-rounding scale-back. Collides with Pascal
   Hypot (overloaded Double/Single) -> __crtl_hypot behind a math.h macro
   (the b377 binding landmine). 30k-sweep: 34 diffs vs runtime glibc, all
   glibc misrounds (judged against 100-digit references). */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include <math.h>
static int ck(double v, const char *want, int code) {
    char b[64];
    snprintf(b, sizeof b, "%.17g", v);
    if (strcmp(b, want) != 0) { printf("FAIL %d got=%s want=%s\n", code, b, want); return code; }
    return 0;
}
int main(void) {
    unsigned long long ms = 1ull;                  /* min subnormal via bits */
    double m = *(double *)&ms;
    double inf = 1.0 / 0.0, nan0 = 0.0 / 0.0;
    int r;
    if ((r = ck(hypot(3.0, 4.0), "5", 1))) return r;
    if ((r = ck(hypot(1.0, 1.0), "1.4142135623730951", 2))) return r;
    if ((r = ck(hypot(0.3, 0.4), "0.5", 3))) return r;
    if ((r = ck(hypot(1e308, 1e308), "1.4142135623730951e+308", 4))) return r;
    if ((r = ck(hypot(1e-300, 1e-300), "1.414213562373095e-300", 5))) return r;
    if ((r = ck(hypot(m, m), "4.9406564584124654e-324", 6))) return r;
    if ((r = ck(hypot(1.0, 1e-200), "1", 7))) return r;
    if ((r = ck(hypot(0.0, -7.0), "7", 8))) return r;
    if ((r = ck(hypot(inf, nan0), "inf", 9))) return r;
    if ((r = ck(hypot(nan0, 2.0), "-nan", 10))) return r;
    printf("ok\n");
    return 42;
}
