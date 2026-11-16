/* typeof of pointer, struct, member and function-pointer expressions, and
   typeof_unqual (rump-pxx g04 g05; util-linux container_of/min/max).
   feature-c-typeof */
#include <stdio.h>
#include <stddef.h>
#define container_of(ptr, type, member) ({ const typeof(((type *)0)->member) *__mptr = (ptr); \
    (type *)((char *)__mptr - offsetof(type, member)); })
#define max(a, b) ({ typeof(a) _a = (a); typeof(b) _b = (b); _a > _b ? _a : _b; })
struct node { int k; struct node *left; };
struct outer { int x; struct node n; double d; };
static int twice(int v) { return 2 * v; }
int (*fp)(int) = twice;
volatile long t = 40;
long arr[4] = {1, 2, 3, 4};
struct outer g = {7, {5, 0}, 1.5};
__typeof__(g) g2;
int main(void) {
    struct outer *op = &g;
    __typeof__(op) op2 = op;                    /* pointer to struct */
    __typeof__(op->n) nn = op->n;               /* struct member */
    __typeof__(&arr[0]) lp = arr;               /* long pointer: steps 8 */
    __typeof__(fp) f2 = fp;                     /* function pointer */
    __typeof__(*op) copy = *op;                 /* deref of struct pointer */
    const volatile __typeof__(t) *tp = &t;
    const __typeof_unqual__(*tp) tv = *tp;
    struct outer *back = container_of(&g.n, struct outer, n);
    g2 = g;
    lp++;
    printf("%d %d %ld %d\n", op2->x, nn.k, *lp, f2(21));
    printf("%d %.1f %ld %d\n", copy.n.k, copy.d, tv + 2, back->x);
    printf("%d %d %d\n", g2.x, max(3, 9), (int)sizeof(__typeof__(g)));
    return 0;
}
