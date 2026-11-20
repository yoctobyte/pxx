/* ++/--/op= whose VALUE is used, on a plain variable: lowered without the
   variable's address (shared IR, AN_INCDEC / AN_COMPOUND_ASSIGN), so the
   copy loop `*d++ = *s++` keeps its pointers on the register path.
   Every row is sequenced, so gcc's output is the reference. Rainyday 0060. */
#include <stdio.h>
#include <stdint.h>
struct P { int a; double b; };
static int g = 5;
static long gl = 10;

static void copy(unsigned char *d, const unsigned char *s, size_t n)
{
    while (n--)
        *d++ = *s++;
}

int main(void)
{
    int i = 3; long l = -2; unsigned u = 0; uint64_t q = ~0ULL; short sh = 32767; char c = 'a';
    double d = 1.5; struct P arr[3] = {{1, 1.0}, {2, 2.0}, {3, 3.0}}; struct P *p = arr;
    int ia[4] = {10, 20, 30, 40}; int *ip = ia;
    int a = i++; int b = ++i; int e = i--; int f = --i;
    printf("%d %d %d %d %d\n", a, b, e, f, i);
    long l1 = l++; long l2 = ++l; printf("%ld %ld %ld\n", l1, l2, l);
    unsigned u1 = u--; printf("%u %u\n", u1, u);
    unsigned long long q1 = q++; printf("%llu %llu\n", q1, (unsigned long long)q);
    short s1 = sh++; printf("%d %d\n", s1, sh);
    char c1 = c++; printf("%c %c\n", c1, c);
    double d1 = d++; double d2 = ++d; printf("%g %g %g\n", d1, d2, d);
    int pa = (p++)->a; int pb = (++p)->a; printf("%d %d %d\n", pa, pb, p->a);
    int i1 = *ip++; int i2 = *++ip; printf("%d %d %d\n", i1, i2, *ip);
    int g1 = g++; int g2 = ++g; long g3 = gl--; printf("%d %d %ld %ld\n", g1, g2, g3, gl);
    int x = 7; x += 5; x -= 2; x *= 3; x /= 4; x %= 5; x <<= 3; x >>= 1; x |= 1; x &= 13; x ^= 6;
    printf("%d\n", x);
    int y = 1; int z = (y += 4) * 2; printf("%d %d\n", y, z);
    p = arr; p += 2; printf("%d\n", p->a); p -= 1; printf("%d\n", p->a);
    unsigned char uc = 250; uc += 10; printf("%d\n", uc);
    int k = 0; for (int j = 0; j < 5; j++, k += j) ; printf("%d\n", k);
    static int sk = 1; sk *= 7; int sk1 = sk++; printf("%d %d\n", sk1, sk);
    unsigned char src[37], dst[40] = {0};
    for (int t = 0; t < 37; t++) src[t] = (unsigned char)(t * 7 + 1);
    copy(dst + 1, src, 37);
    unsigned sum = 0; for (int t = 0; t < 40; t++) sum = sum * 31 + dst[t];
    printf("%u %d %d\n", sum, dst[0], dst[39]);
    return 0;
}
