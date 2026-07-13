/* A multidimensional LOCAL array of STRUCTS must honour its brace initializer.

   The local array-of-record initializer called the brace-elision walker with nDims
   hard-coded to 1, so a multidim array was walked as if it were one-dimensional: only
   the first element landed and every other stayed zero. Silent -- no error, no warning.

   The GLOBAL path already derived the real shape from SymArrNDims/SymArrDimSpan
   (CEmitDeferredCAggInits); the local one just didn't. It now does.

   Found by the csmith fuzzer (seed 2503: `const struct S0 l_55[6][5][8] = {...}`). */
int printf(const char *, ...);

struct S0 { int f0; };
struct S2 { int a; int b; };

int main(void)
{
    struct S0 a[2][3]    = {{{1},{2},{3}}, {{4},{5},{6}}};
    struct S0 t[2][2][2] = {{{{1},{2}},{{3},{4}}}, {{{5},{6}},{{7},{8}}}};
    struct S2 m[2][2]    = {{{1,2},{3,4}}, {{5,6},{7,8}}};
    struct S0 flat[6]    = {{1},{2},{3},{4},{5},{6}};   /* 1-D: was always fine */

    printf("2d=%d %d %d\n", a[0][0].f0, a[1][0].f0, a[1][2].f0);
    printf("3d=%d %d %d\n", t[0][0][0].f0, t[1][0][1].f0, t[1][1][1].f0);
    printf("2f=%d %d %d %d\n", m[0][0].a, m[0][1].b, m[1][0].a, m[1][1].b);
    printf("1d=%d %d\n", flat[0].f0, flat[5].f0);
    return 0;
}
