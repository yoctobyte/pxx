/* Guard: variadic C function with a NAMED floating-point parameter before the
   `...`. va_start must seed fp_offset past the named XMM arg(s), else the first
   va_arg(double) rereads the named param. Regression test for
   bug-c-vararg-vastart-named-fp-stack (register-class case).
   Expected program exit code: 42 on success. */
#include <stdarg.h>

static double sumv(double scale, int n, ...) {
    va_list ap;
    double acc = 0.0;
    int i;
    va_start(ap, n);
    for (i = 0; i < n; i++)
        acc += va_arg(ap, double);
    va_end(ap);
    return scale * acc;   /* scale=2.0, acc=1+2+3=6 -> 12.0 */
}

int main(void) {
    double r = sumv(2.0, 3, 1.0, 2.0, 3.0);
    /* exact: 2.0 * 6.0 = 12.0 */
    if (r > 11.999 && r < 12.001) return 42;
    return 1;
}
