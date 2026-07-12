/* crtl copysign/isinf/nextafter/signbit: bit-level bodies with NO libc
   fallback (they have no Pascal RTL counterpart for the case-insensitive
   extern bind, so a missing body used to become a silent DT_NEEDED).
   gcc-oracle parity: this file exits 42 under both. Exercises -0.0, NaN
   sign, subnormal crossing, one-ULP round-trip. */
#include <math.h>
#include <stdio.h>
int main(void) {
    double negz = -0.0;
    /* copysign incl -0 and NaN-payload sign */
    if (copysign(3.0, -1.0) != -3.0) { printf("cs1\n"); return 1; }
    if (copysign(-3.0, 1.0) != 3.0) { printf("cs2\n"); return 1; }
    if (signbit(copysign(0.0, negz)) != 1) { printf("cs-negz\n"); return 1; }
    if (!signbit(copysign(nan(""), -1.0))) { printf("cs-nan\n"); return 1; }
    /* signbit bit-exact */
    if (signbit(negz) != 1 || signbit(0.0) != 0 || signbit(-1e-300) != 1) { printf("sb\n"); return 1; }
    /* isinf */
    if (!isinf(1.0/0.0) || !isinf(-1.0/0.0) || isinf(nan("")) || isinf(1e308)) { printf("inf\n"); return 1; }
    /* nextafter: one ULP up from 1.0 then back */
    if (nextafter(1.0, 2.0) <= 1.0) { printf("na1\n"); return 1; }
    if (nextafter(nextafter(1.0, 2.0), 0.0) != 1.0) { printf("na2\n"); return 1; }
    if (nextafter(0.0, 1.0) <= 0.0) { printf("na3\n"); return 1; }
    if (nextafter(0.0, -1.0) >= 0.0) { printf("na4\n"); return 1; }
    if (nextafter(5.0, 5.0) != 5.0) { printf("na5\n"); return 1; }
    if (!(nextafter(nan(""), 1.0) != nextafter(nan(""), 1.0))) { printf("na6\n"); return 1; }
    /* remainder + asinh still good through the restored copysign path */
    if (remainder(5.0, 3.0) != -1.0) { printf("rem\n"); return 1; }
    if (asinh(-0.5) + asinh(0.5) != 0.0) { printf("as\n"); return 1; }
    return 42;
}
