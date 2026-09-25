/* A C program that includes <math.h> builds and runs on wasm32.
 *
 * It was refused with `wasm: var-name pool full`. The pool was not too small:
 * a wasm body emitted in chunks is resumed, and each resume copied its whole
 * local-name list back into the pool while leaving the old copy behind. At the
 * point of failure 3819 of 65244 entries were live. The encoder now compacts
 * the pools when one is about to overflow.
 *
 * The make row diffs this against gcc's build. %.6f and integer results only,
 * so the comparison is about the values and not about the last digit of a
 * %g. */
#include <stdio.h>
#include <math.h>

int main(void)
{
    double x = 2.0;
    printf("%.6f %.6f %.6f %.6f\n", sqrt(x), pow(x, 10.0), exp(1.0), log(10.0));
    printf("%.6f %.6f %.6f %.6f\n", sin(0.5), cos(0.5), atan2(1.0, 1.0), fabs(-3.25));
    printf("%.1f %.1f %.1f %.6f\n", floor(-2.5), ceil(-2.5), round(2.5), fmod(7.5, 2.0));
    printf("%d %d\n", (int)hypot(3.0, 4.0), isnan(NAN) != 0);
    return 0;
}
