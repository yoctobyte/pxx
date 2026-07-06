/* Regression: C struct field designators `.field = v` in braced initializers
   (C 6.7.8), global and local, positional/designated mixes. Pre-fix pxx filled
   fields in declaration order and ignored the designator. Returns 42. */
struct S { int a; int b; int c; };

struct S g1 = { .b = 2, .a = 1 };          /* out-of-order designators */
struct S g2 = { 9, .c = 3 };               /* positional then designator */

int x = 10;
struct P { int a; int *p; };
struct P g3 = { .p = &x, .a = 1 };         /* designator + address-of global */

int main(void) {
    struct S l = { .c = 30, .a = 10 };     /* local, designated */
    if (g1.a != 1 || g1.b != 2) return 1;
    if (g2.a != 9 || g2.c != 3) return 2;   /* g2.b defaults to 0 */
    if (g2.b != 0) return 3;
    if (g3.a != 1 || *g3.p != 10) return 4;
    if (l.a != 10 || l.c != 30 || l.b != 0) return 5;
    return 42;
}
