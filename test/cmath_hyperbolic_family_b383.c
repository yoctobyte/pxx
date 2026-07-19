/* Correctly-rounded crtl hyperbolics (b383, follow-on to b377-b382):
   sinh/cosh/tanh on the shared exp reduction (small-x sinh by odd Taylor —
   the exp difference cancels below ~0.35), asinh/acosh/atanh on dd sqrt +
   the dd-input log kernel. Three landmines this test pins:
   - sinh/cosh/tanh collide case-insensitively with Pascal Sinh/Cosh/Tanh
     (the b377 binding landmine) -> __crtl_ names + math.h macros;
   - crtl_dd_muld(v, -1.0) Dekker-splits v and OVERFLOWS above ~2^996 —
     asinh/acosh(x ~ 2^499) squared to 2^998 and returned NaN; negation is
     now a component-wise crtl_dd_neg;
   - tiny-x atanh through (1+x)/(1-x) turns absolute dd error into
     half-ulp relative error -> direct odd series below 2^-30.
   30k-random sweeps per function: every diff vs runtime glibc judged
   against 100-digit references was a glibc misround. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include <math.h>   /* the __crtl_ function-like macros */
static int ck(double v, const char *want, int code) {
    char b[64];
    snprintf(b, sizeof b, "%.17g", v);
    if (strcmp(b, want) != 0) { printf("FAIL %d got=%s want=%s\n", code, b, want); return code; }
    return 0;
}
int main(void) {
    unsigned long long big = 0x5F2BBD7705504C55ull;   /* ~2^499.7: the NaN case */
    int r;
    if ((r = ck(sinh(1.0), "1.1752011936438014", 1))) return r;
    if ((r = ck(sinh(-2.0), "-3.6268604078470186", 2))) return r;   /* glibc runtime: ...19 */
    if ((r = ck(sinh(0.01), "0.010000166667500003", 3))) return r;
    if ((r = ck(sinh(700.0), "5.0711602736750225e+303", 4))) return r;
    if ((r = ck(sinh(711.0), "inf", 5))) return r;
    if ((r = ck(cosh(1.0), "1.5430806348152437", 6))) return r;
    if ((r = ck(cosh(10.0), "11013.232920103323", 7))) return r;    /* glibc runtime: ...24 */
    if ((r = ck(cosh(0.0), "1", 8))) return r;
    if ((r = ck(tanh(0.5), "0.46211715726000974", 9))) return r;
    if ((r = ck(tanh(-1.0), "-0.76159415595576485", 10))) return r;
    if ((r = ck(tanh(25.0), "1", 11))) return r;
    if ((r = ck(asinh(1.0), "0.88137358701954305", 12))) return r;
    if ((r = ck(asinh(-3.5), "-1.9657204716496515", 13))) return r;
    if ((r = ck(asinh(1e-15), "1.0000000000000001e-15", 14))) return r;
    if ((r = ck(asinh(*(double *)&big), "347.123880482441", 15))) return r;  /* was NaN */
    if ((r = ck(acosh(1.0), "0", 16))) return r;
    if ((r = ck(acosh(2.0), "1.3169578969248168", 17))) return r;
    if ((r = ck(acosh(1.0000001), "0.0004472135919037347", 18))) return r;
    if ((r = ck(atanh(0.5), "0.54930614433405489", 19))) return r;
    if ((r = ck(atanh(-0.99), "-2.6466524123622457", 20))) return r;
    if ((r = ck(atanh(1e-15), "1.0000000000000001e-15", 21))) return r;
    if ((r = ck(atanh(1.0), "inf", 22))) return r;
    printf("ok\n");
    return 42;
}
