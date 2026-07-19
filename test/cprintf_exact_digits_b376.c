/* Exact printf digit generation (b376): the old scaled-multiply extraction
   left the double's exact-integer range at >= 16 significant digits (sqrt(2)
   %.16e printed ...52, glibc ...51 — every quickjs Math.* result carried a
   1-ulp tail), and huge/tiny magnitudes lost integer digits entirely. All
   expected strings below verified against glibc output. Also checks the
   rounding-mode hook (quickjs toFixed probes FE_DOWNWARD through snprintf). */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include <fenv.h>
static int ck(const char *got, const char *want, int code) {
    if (strcmp(got, want) != 0) { printf("FAIL %d got=%s want=%s\n", code, got, want); return code; }
    return 0;
}
int main(void) {
    char b[600]; int r;
    double s2 = sqrt(2.0);
    snprintf(b, sizeof b, "%.16e", s2);
    if ((r = ck(b, "1.4142135623730951e+00", 1))) return r;
    snprintf(b, sizeof b, "%.17e", s2);
    if ((r = ck(b, "1.41421356237309515e+00", 2))) return r;
    snprintf(b, sizeof b, "%.17g", 0.1);
    if ((r = ck(b, "0.10000000000000001", 3))) return r;
    snprintf(b, sizeof b, "%.2f", 1e21);
    if ((r = ck(b, "1000000000000000000000.00", 4))) return r;
    snprintf(b, sizeof b, "%.6f", 1.7976931348623157e308);
    if (strlen(b) != 316) { printf("FAIL 5 len=%d\n", (int)strlen(b)); return 5; }
    snprintf(b, sizeof b, "%.15g", 123456789.123456789);
    if ((r = ck(b, "123456789.123457", 6))) return r;
    /* ties-to-even at the cut under the default mode */
    snprintf(b, sizeof b, "%.0f", 0.5);
    if ((r = ck(b, "0", 7))) return r;
    snprintf(b, sizeof b, "%.0f", 1.5);
    if ((r = ck(b, "2", 8))) return r;
    /* FE_DOWNWARD honored (glibc parity; quickjs js_fcvt rides this) */
    fesetround(FE_DOWNWARD);
    snprintf(b, sizeof b, "%.4f", 1.005);
    fesetround(FE_TONEAREST);
    if ((r = ck(b, "1.0049", 9))) return r;
    printf("ok\n");
    return 42;
}
