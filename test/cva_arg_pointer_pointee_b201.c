/* b201: va_arg(ap, T*) must remember it points at T, so `*va_arg(ap,T*) = v`
   stores at T's width. Previously the result collapsed to a bare pointer, so
   the deref defaulted to int and a wider store truncated: sscanf's
   `*va_arg(ap,double*) = strtod(...)` wrote the integer bits of the value
   (100.125 -> 4.94e-322). Fixed by threading the pointee via a PTR_CAST alias.
   (bug-crtl-printf-g-double-roundtrip, scanf-float defect.) */
#include <stdio.h>
#include <stdarg.h>

static int stored(int dummy, ...) {
    va_list ap; va_start(ap, dummy);
    *va_arg(ap, double *) = 100.125;      /* double through va_arg pointer */
    va_end(ap); return 1;
}
static int storef(int dummy, ...) {
    va_list ap; va_start(ap, dummy);
    *va_arg(ap, float *) = 3.25f;
    va_end(ap); return 1;
}

int main(void) {
    double d = 0; stored(0, &d);
    if (d != 100.125) return 1;

    float f = 0; storef(0, &f);
    if (f != 3.25f) return 2;

    /* the real-world path: sscanf float conversions delegate to va_arg(T*) */
    double s = 0; sscanf("100.125", "%lf", &s);
    if (s != 100.125) return 3;
    float sf = 0; sscanf("3.25", "%f", &sf);
    if (sf != 3.25f) return 4;

    return 42;
}
