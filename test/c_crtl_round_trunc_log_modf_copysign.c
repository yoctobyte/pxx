/* SPDX-License-Identifier: Zlib */
/* round, lround, llround, trunc, log2, log10, modf and copysign from crtl
   itself (no libc), on edge values, against gcc + glibc. Row c_rndlog26.
   The output is the bit pattern, so -0.0 and NaN sign show.
   bug-crtl-declares-round-trunc-log2-and-others-it-does-not-define */
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <float.h>

static unsigned long long bits(double d)
{
    unsigned long long u;
    memcpy(&u, &d, sizeof u);
    return u;
}

int main(void)
{
    double v[] = { 0.0, -0.0, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5, 0.49999999999999994,
                   1e15 + 0.5, 4503599627370497.0, -7.75, 1e300, DBL_MIN / 8,
                   HUGE_VAL, -HUGE_VAL, NAN };
    double lg[] = { 1.0, 2.0, 8.0, 1024.0, 0.125, 10.0, 1000.0, 1e-5, 3.0, 7.0,
                    1e300, DBL_MIN, DBL_MIN / 8, 0.0, -1.0, HUGE_VAL };
    unsigned i;
    for (i = 0; i < sizeof v / sizeof v[0]; i++) {
        double ip, fr = modf(v[i], &ip);
        printf("v%-2u round %016llx trunc %016llx modf %016llx %016llx cs %016llx %016llx\n", i,
               bits(round(v[i])), bits(trunc(v[i])), bits(fr), bits(ip),
               bits(copysign(3.0, v[i])), bits(copysign(v[i], -1.0)));
        if (fabs(v[i]) < 1e18)
            printf("    lround %ld llround %lld\n", lround(v[i]), llround(v[i]));
    }
    for (i = 0; i < sizeof lg / sizeof lg[0]; i++)
        printf("l%-2u log2 %016llx log10 %016llx\n", i, bits(log2(lg[i])), bits(log10(lg[i])));
    return 0;
}
