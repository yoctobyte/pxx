/* ESP: C integer / and % by zero give 0, like Pascal's div and mod there.
   C calls it undefined, so 0 is a legal answer, and it is the one that keeps a
   device running. Covers the compound forms, which the C frontend desugars
   through the same operator, and all three widths. `volatile` keeps the zero
   opaque to the folder. decide-int-div-zero-behavior-unification */
#include <stdio.h>
int main(int argc, char **argv) {
    volatile int z = 0; int a = 17, b = z; long long qa = 17, qb = z; unsigned ua = 17, ub = z;
    int c = a; c /= b; int d = a; d %= b;
    printf("c div %d mod %d ll %lld %lld u %u %u cmp %d %d\n", a / b, a % b, qa / qb, qa % qb, ua / ub, ua % ub, c, d);
    b = 5; printf("nonzero %d %d\n", a / b, -a % b);
    return 0;
}
