/* Correctly-rounded crtl log2/log10/expm1/log1p (b382, follow-on to
   b377-b380): log2/log10 = dd log times dd 1/ln2 resp. 1/ln10 (keeps
   log2(2^n)=n and log10(10^n)=n exact — the old Pascal bridge gave
   log10(1000)=2.9999999999999996); expm1/log1p on the dd kernels (the old
   1e-5-threshold series lost ~10 digits right AT its cutoff:
   expm1(1e-5) = ...069649 instead of ...166668).
   log2/log10 collide case-insensitively with Pascal Log2/Log10 — same
   binding landmine as exp/Exp (b377) — so they live under __crtl_ names
   behind math.h function-like macros. Expected strings verified against
   100-digit decimal references; sweeps: every glibc diff was a glibc
   misround (glibc log10 misrounds ~14% of args!). */
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
    int r;
    if ((r = ck(log2(8.0), "3", 1))) return r;
    if ((r = ck(log2(10.0), "3.3219280948873622", 2))) return r;
    if ((r = ck(log2(0.7), "-0.51457317282975834", 3))) return r;
    if ((r = ck(log10(1000.0), "3", 4))) return r;      /* was 2.9999999999999996 */
    if ((r = ck(log10(2.0), "0.3010299956639812", 5))) return r;
    if ((r = ck(log10(1e15), "15", 6))) return r;
    if ((r = ck(expm1(0.5), "0.64872127070012819", 7))) return r;
    if ((r = ck(expm1(1e-5), "1.0000050000166668e-05", 8))) return r;
    if ((r = ck(expm1(-0.3), "-0.25918177931828212", 9))) return r;
    if ((r = ck(expm1(30.0), "10686474581523.463", 10))) return r;
    if ((r = ck(expm1(-40.0), "-1", 11))) return r;
    if ((r = ck(log1p(0.5), "0.40546510810816438", 12))) return r;
    if ((r = ck(log1p(1e-5), "9.9999500003333319e-06", 13))) return r;
    if ((r = ck(log1p(-0.3), "-0.35667494393873234", 14))) return r;
    if ((r = ck(log1p(1e300), "690.77552789821368", 15))) return r;
    if ((r = ck(log1p(1e-12), "9.9999999999949996e-13", 16))) return r;
    if ((r = ck(log1p(-1.0), "-inf", 17))) return r;
    printf("ok\n");
    return 42;
}
