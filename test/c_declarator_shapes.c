/* Declarator shapes NetBSD's headers use (rump-pxx g06 g07 g08 g23):
   several names in one typedef, a qualifier after a struct typedef body,
   a parenthesised function typedef name, several function-pointer
   declarators in one declaration. And a typedef named X, which crtl's own
   printf (a block-scope `static struct __crtl_dexp X`) must not see. */
#include <stdio.h>
typedef int A, *PA, ARR[3];
typedef struct x { int v; } X, *PX;
typedef struct { int a, b; } AN, *PAN, ANA[2];
typedef enum { E1, E2, E3 } EE, *PEE;
typedef struct mi { int v; } const mi_t;
typedef int (imp_t)(int, int);
struct s { imp_t *fn; };
typedef void (*pf_t)(int);
static int acc;
static void add(int v) { acc += v; }
static void mul(int v) { acc *= v; }
pf_t a = add, b = mul;
void (*c)(int) = add, (*d)(int) = mul;
extern pf_t ea, eb;
pf_t ea = add, eb = add;
static const mi_t mic = { 41 };
static int plus(int x, int y) { return x + y; }
int main(void) {
    A i = 3; PA pi = &i; ARR arr = {1, 2, 3};
    X xv = { 5 }; PX px = &xv;
    AN an = { 1, 2 }; PAN pan = &an; ANA ana;
    EE e = E3; PEE pe = &e;
    struct s sv = { plus };
    ana[1].b = 9;
    printf("%d %d %d %d\n", *pi, (int)sizeof(ARR), arr[2], px->v);
    printf("%d %d %d %d\n", pan->b, (int)sizeof(ANA), ana[1].b, *pe);
    printf("%d %d\n", mic.v, sv.fn(20, 22));
    a(2); b(5); c(1); d(3); ea(1); eb(1);
    printf("%d\n", acc);
    printf("%.2f\n", 2.5);
    return 0;
}
