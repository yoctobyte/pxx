/* Shapes that compiled and came out WRONG (rump-pxx's silent gaps).
   S10 bug-c-a-later-declarators-const-after-the-star-was-not-skipped
   S11 bug-c-a-function-declared-through-a-function-typedef-became-an-object
   S6  bug-c-attribute-mode-qi-hi-si-di-was-ignored
   S7  bug-c-a-cast-to-a-union-used-the-value-as-the-unions-address */
#include <stdio.h>

/* S10: `const` after a later declarator's star */
struct s { int * const m1, * const m2; int z; };
extern const int * const ea, * const eb;
const int ev = 41;
const int * const ea = &ev, * const eb = &ev;

/* S11: declared through a function TYPE typedef */
typedef int d_open_t(int, int);
typedef const char *namefn_t(void);
d_open_t yopen, yclose;
extern d_open_t yext;
static d_open_t ystat;
namefn_t myname;
d_open_t *fp = yopen;
int yopen(int a, int b) { return a + b; }
int yclose(int a, int b) { return a * b; }
int yext(int a, int b) { return a - b; }
static int ystat(int a, int b) { return a << b; }
const char *myname(void) { return "me"; }

/* S6: mode(..) */
typedef int di_t __attribute__((__mode__(__DI__)));
typedef unsigned int qi_t __attribute__((__mode__(__QI__)));
typedef int __attribute__((mode(HI))) hi_t;
typedef unsigned int udi_t __attribute__((mode(DI)));
typedef int si_t __attribute__((mode(SI)));
typedef unsigned uw_t __attribute__((mode(word)));

/* S7: GNU cast to a union */
union u { int i; float f; };
union w { double d; char *p; long l; };
static int takes(union u v) { return v.i; }

int main(void)
{
    int x = 3, y = 4;
    int * const p = &x, * const q = &y;
    struct s v = { &x, &y, 9 };
    di_t a = -1;
    qi_t qq = 300;
    hi_t h = 70000;
    udi_t uu = 0;
    char buf[] = "hi";
    union u ux = (union u)5, uy = (union u)1.5f;
    union w wa = (union w)buf, wb = (union w)2.5, wc = (union w)7L;

    printf("S10 %d %d %d %d %d %zu %d\n", *p, *q, *v.m1, *v.m2, v.z, sizeof(struct s), *ea + *eb);
    printf("S11 %d %d %d %d %s %d\n", yopen(2, 3), yclose(2, 3), yext(5, 1), ystat(1, 4), myname(), fp(10, 1));
    a <<= 40; uu--;
    printf("S6 %zu %zu %zu %zu %zu %zu %lld %u %d %llu\n", sizeof(di_t), sizeof(qi_t), sizeof(hi_t),
           sizeof(udi_t), sizeof(si_t), sizeof(uw_t), (long long)a, (unsigned)qq, (int)h, (unsigned long long)uu);
    printf("S7 %d %.1f %s %.1f %ld %d %d\n", ux.i, uy.f, wa.p, wb.d, wc.l, takes((union u)9), ((union u)11).i);
    return 0;
}
