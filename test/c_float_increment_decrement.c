/* ++ and -- on floating operands, against gcc: the step is 1.0, not the
   double whose bit pattern is the integer 1. Every form awk uses: pre and
   post, as a statement and as a value, float/double/long double, a struct
   field, an array element, through a pointer, and the `while (k-- > 0)` loop
   that never ended. bug-c-increment-and-decrement-of-a-double-add-integer-bits */
#include <stdio.h>
struct var { int type; double number; float f; };
int main(void)
{
    double a = 5, b = 7, n = 0, k = 3, c = 3, d, e, f, g;
    float x = 1.5f, y;
    long double L = 10;
    double arr[3] = { 1, 2, 3 };
    struct var v = { 0, 5, 2.5f }, *pv = &v;
    double *p = &arr[1];
    int i = 0;
    a++; b--;
    while (k-- > 0) n++;
    d = c++; e = ++c; f = c--; g = --c;
    y = x++; ++x; x--;
    L++; --L; L++;
    arr[2]++; --arr[0]; (*p)++; ++*p;
    pv->number++; v.f--; --pv->f;
    for (double t = 0.5; t < 3; t++) i++;
    printf("%g %g %g %g | %g %g %g %g %g\n", a, b, n, k, d, e, f, g, c);
    printf("%g %g %Lg | %g %g %g | %g %g | %d\n", (double)x, (double)y, L,
           arr[0], arr[1], arr[2], v.number, (double)v.f, i);
    return 0;
}
