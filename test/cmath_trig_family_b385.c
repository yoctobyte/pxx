/* Correctly-rounded crtl trigonometry (b385, follow-on to b377-b384):
   sin/cos/tan via Cody-Waite pi/2 reduction (three 24-bit chunks + dd
   tail, |x| < 1e8; beyond that the Pascal fallback stays — huge-argument
   Payne-Hanek is a noted gap) and 13-term dd Taylor kernels; tan =
   sin/cos in dd. asin/acos/atan/atan2 via a dd atan kernel (half-angle
   reduction + alternating odd series) and exact 1-x^2 factorizations.
   sin/cos/tan collide case-insensitively with Pascal Sin/Cos/Tan (the
   b377 binding landmine) -> __crtl_ names + math.h macros; the inverse
   names don't collide (Pascal ArcSin etc.) and are plain definitions.
   30k-random sweeps per function judged against 130-digit references:
   every diff vs runtime glibc was a glibc misround. */
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
    int r;
    if ((r = ck(sin(1.0), "0.8414709848078965", 1))) return r;
    if ((r = ck(sin(-2.0), "-0.90929742682568171", 2))) return r;
    if ((r = ck(sin(1e6), "-0.34999350217129294", 3))) return r;
    if ((r = ck(sin(3.141592653589793), "1.2246467991473532e-16", 4))) return r;
    if ((r = ck(cos(1.0), "0.54030230586813977", 5))) return r;
    if ((r = ck(cos(1.5707963267948966), "6.123233995736766e-17", 6))) return r;
    if ((r = ck(cos(100.0), "0.86231887228768389", 7))) return r;
    if ((r = ck(tan(0.5), "0.54630248984379048", 8))) return r;
    if ((r = ck(tan(1.5707963267948966), "16331239353195370", 9))) return r;
    if ((r = ck(tan(12345.6789), "-0.98971397154430851", 10))) return r;
    if ((r = ck(asin(0.5), "0.52359877559829893", 11))) return r;
    if ((r = ck(asin(-0.999999), "-1.5693821131146521", 12))) return r;
    if ((r = ck(asin(1.0), "1.5707963267948966", 13))) return r;
    if ((r = ck(acos(0.5), "1.0471975511965979", 14))) return r;
    if ((r = ck(acos(0.999999), "0.0014142136802445852", 15))) return r;
    if ((r = ck(acos(-1.0), "3.1415926535897931", 16))) return r;
    if ((r = ck(atan(1.0), "0.78539816339744828", 17))) return r;
    if ((r = ck(atan(-1e10), "-1.5707963266948965", 18))) return r;
    if ((r = ck(atan(1e-300), "1e-300", 19))) return r;
    if ((r = ck(atan2(1.0, 2.0), "0.46364760900080609", 20))) return r;
    if ((r = ck(atan2(-3.0, -4.0), "-2.4980915447965089", 21))) return r;
    if ((r = ck(atan2(0.0, -1.0), "3.1415926535897931", 22))) return r;
    if ((r = ck(atan2(-5.0, 0.0), "-1.5707963267948966", 23))) return r;
    printf("ok\n");
    return 42;
}
