/* Differential libm sweep (feature-crtl-libm-correctly-rounded-transcendentals):
   build this same source with gcc (glibc libm) and pxx (crtl libm), run both,
   diff the outputs. argv[1] = exp|log|cbrt|pow, argv[2] = count (default 100000).

     gcc -O1 tools/libm_diff_sweep.c -lm -o /tmp/sw_gcc
     compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src tools/libm_diff_sweep.c /tmp/sw_pxx
     /tmp/sw_gcc exp > /tmp/g.txt; /tmp/sw_pxx exp > /tmp/p.txt; diff /tmp/g.txt /tmp/p.txt

   IMPORTANT (2026-07-19 findings): crtl's exp/log/pow/cbrt are CORRECTLY
   ROUNDED (double-double kernels); runtime glibc is NOT — its documented
   >0.5-ulp bounds misround ~6e-4 (exp), ~1e-4 (log), ~9e-4 (pow) and ~55%
   (cbrt!) of random args. So a nonzero diff count against glibc is expected;
   judge each diff against a high-precision reference (python decimal, 80+
   digits) before assuming a crtl bug — in the 2026-07 sweeps EVERY diff was a
   glibc misround. gcc's compile-time MPFR constant folding, by contrast,
   agrees with crtl exactly. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

static unsigned long long s = 0x9E3779B97F4A7C15ull;
static unsigned long long rnd(void) {
    s ^= s << 13; s ^= s >> 7; s ^= s << 17;
    return s;
}
static double rndu(void) {   /* uniform in [0,1) */
    return (double)(rnd() >> 11) / 9007199254740992.0;
}

int main(int argc, char **argv) {
    const char *fn = argc > 1 ? argv[1] : "exp";
    int n = argc > 2 ? atoi(argv[2]) : 100000;
    int i;
    char b[64];
    if (strcmp(fn, "exp") == 0) {
        static const double sp[] = { 0.0, 1.0, -1.0, 2.0, 0.5, 709.782712893384,
            -745.1332191019412, 0.6931471805599453, -0.6931471805599453,
            1e-300, -1e-300, 708.0, -708.0, 710.0, -746.0 };
        for (i = 0; i < 15; i++) { snprintf(b, sizeof b, "%.17g", exp(sp[i])); puts(b); }
        for (i = 0; i < n; i++) {
            double x;
            if (i % 3 == 0) x = -745.0 + 1455.0 * rndu();          /* full range */
            else if (i % 3 == 1) x = (rndu() - 0.5) * ldexp(1.0, (int)(rndu()*70.0) - 60);  /* tiny/medium */
            else x = (rndu() - 0.5) * 2.0 * 709.0 * rndu();        /* mixed */
            snprintf(b, sizeof b, "%.17g", exp(x)); puts(b);
        }
    } else if (strcmp(fn, "log") == 0) {
        static const double sp[] = { 1.0, 2.0, 10.0, 0.5, 2.718281828459045,
            4.0, 1e300, 1e-300, 3.0, 7.0 };
        for (i = 0; i < 10; i++) { snprintf(b, sizeof b, "%.17g", log(sp[i])); puts(b); }
        for (i = 0; i < n; i++) {
            double x;
            if (i % 3 == 0) x = ldexp(1.0 + rndu(), (int)(rndu()*2045.0) - 1022);
            else if (i % 3 == 1) x = 1.0 + (rndu() - 0.5) * ldexp(1.0, -(int)(rndu()*50.0));  /* near 1 */
            else x = rndu() * 1000.0;
            if (x <= 0.0) x = 1.5;
            snprintf(b, sizeof b, "%.17g", log(x)); puts(b);
        }
    } else if (strcmp(fn, "cbrt") == 0) {
        static const double sp[] = { 0.0, 1.0, -1.0, 8.0, -8.0, 27.0, -27.0,
            2.0, 64.0, 1e300, 1e-300, -1e300, 0.001, 216.0, 729.0 };
        for (i = 0; i < 15; i++) { snprintf(b, sizeof b, "%.17g", cbrt(sp[i])); puts(b); }
        for (i = 0; i < n; i++) {
            double x = ldexp(1.0 + rndu(), (int)(rndu()*2045.0) - 1022);
            if (rnd() & 1) x = -x;
            snprintf(b, sizeof b, "%.17g", cbrt(x)); puts(b);
        }
    } else if (strcmp(fn, "pow") == 0) {
        static const double spx[] = { 2.0, 2.0, 10.0, 2.0, 0.5, -2.0, -2.0, 3.0, 1.0000000000000002, 0.9999999999999999 };
        static const double spy[] = { 0.5, 10.0, 3.0, -1.5, 100.0, 3.0, 4.0, 0.3333333333333333, 1e15, 1e15 };
        for (i = 0; i < 10; i++) { snprintf(b, sizeof b, "%.17g", pow(spx[i], spy[i])); puts(b); }
        for (i = 0; i < n; i++) {
            double x, y, w;
            if (i % 4 == 3) {                       /* negative base, integer y */
                x = -ldexp(1.0 + rndu(), (int)(rndu()*40.0) - 20);
                y = (double)((int)(rndu()*80.0) - 40);
            } else {
                x = ldexp(1.0 + rndu(), (int)(rndu()*80.0) - 40);
                y = (rndu() - 0.5) * 60.0;
            }
            w = y * log2(x < 0.0 ? -x : x);
            if (w > 1020.0 || w < -1070.0 || x == 0.0) { x = 2.0; y = rndu(); }
            snprintf(b, sizeof b, "%.17g", pow(x, y)); puts(b);
        }
    } else {
        printf("unknown fn\n");
        return 1;
    }
    return 0;
}
