/* Named params spilled to the caller stack + variadic tail
   (bug-c-vararg-vastart-named-fp-stack, the stack-spilled half):
   - 7th+ named GP arg and 9th+ named FP arg live on the caller stack;
     reading them was broken (missing stack-DOUBLE store in the x86-64
     param homing) and the 17th+ parameter was silently DROPPED (read as
     constant 0 in the body; now a hard compile error above MAX_PROC_PARAMS).
   - overflow_arg_area must start PAST the spilled named params, and the
     va_start register-class seeds must be capped at 6 GP / 8 FP.
   Oracle values verified against gcc. */
#include <stdio.h>
#include <stdarg.h>

int sum_tail(int a1, int a2, int a3, int a4, int a5, int a6, int a7, int n, ...) {
    va_list ap; int s = 0, i;
    va_start(ap, n);
    for (i = 0; i < n; i++) s += va_arg(ap, int);
    va_end(ap);
    return a7 * 1000 + s;
}

double named9(double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8,double d9,double d10) {
    return d9 * 100.0 + d10;
}

double mixed(int i1,int i2,int i3,int i4,int i5,int i6,int i7,int i8,
             double d1,double d2,double d3,double d4,double d5,double d6,double d7,
             int n, ...) {
    va_list ap; double s = 0; int k;
    va_start(ap, n);
    for (k = 0; k < n; k++) {
        if (k % 2 == 0) s += va_arg(ap, int);
        else s += va_arg(ap, double);
    }
    va_end(ap);
    return i7 * 1e6 + i8 * 1e5 + d7 * 1e3 + s;
}

int main(void) {
    printf("%d\n", sum_tail(1,2,3,4,5,6,7, 3, 10, 20, 30));
    printf("%.2f\n", named9(1,2,3,4,5,6,7,8, 9.5, 0.25));
    printf("%.2f\n", mixed(1,2,3,4,5,6,7,8, 1,2,3,4,5,6,7.5, 4, 100, 0.25, 200, 0.5));
    return 0;
}
