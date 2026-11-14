/* Four C shapes pxx refused, each now equal to gcc:
 *  - an index designator inside a multi-dimensional initializer,
 *    bug-c-an-array-designator-inside-a-multi-dimensional-initializer-is-refused
 *  - `sizeof (*p)[1]`, a parenthesised operand with a postfix after it,
 *    bug-c-sizeof-of-a-parenthesised-deref-followed-by-a-subscript-is-refused
 *  - `sizeof f()[1]` / `sizeof h()->b`, a call with a postfix after it,
 *    bug-c-sizeof-without-parentheses-refuses-a-call-followed-by-a-subscript-or-arrow
 *  - `float (*q[2])[4]`, the spelled-out array of pointers to arrays, local
 *    and global, and its typedef twin,
 *    bug-c-the-spelled-out-array-of-pointers-to-arrays-declarator-is-refused
 * Plus a block-scope function prototype (test/c_block_scope_prototype.c is
 * the other-translation-unit half). */
#include <stdio.h>

typedef float mat4[4][4];
typedef float row4[4];
struct H { int a; double b[2]; };
int *fi(void) { static int v[4] = {1, 2, 3, 4}; return v; }
struct H *fh(void) { static struct H h; return &h; }

float ga[4] = {1, 2, 3, 4}, gb[4] = {5, 6, 7, 8};
float gm[4][4];
float (*gq[2])[4] = {&ga, &gb}, gx = 2.5f;
static float (*gr[2])[4][4] = {&gm, &gm};
float (*gu[])[4] = {&gb, &ga, &gb};
float (*gz[3])[4];
struct S { int n; row4 *rows[2]; };

int main(void) {
    /* designators */
    int e[4][3] = {{1}, [3] = {9}};
    int f[3][2] = {[1][1] = 5, [0] = {1, 2}};
    int g3[2][2][2] = {[1] = {[1] = {7, 8}}, [0][0][1] = 3};
    int un[][2] = {[2] = {4, 5}, {6}};
    int r, c, k, sum = 0;
    for (r = 0; r < 4; r++) for (c = 0; c < 3; c++) printf("%d", e[r][c]);
    printf("\n");
    for (r = 0; r < 3; r++) for (c = 0; c < 2; c++) printf("%d", f[r][c]);
    printf("\n");
    for (r = 0; r < 2; r++) for (c = 0; c < 2; c++) for (k = 0; k < 2; k++) printf("%d", g3[r][c][k]);
    printf(" %zu %d %d\n", sizeof un, un[2][1], un[3][0]);

    /* sizeof with a postfix after a group */
    mat4 m; mat4 *p = &m; mat4 *mm[2] = {&m, &m};
    printf("%zu %zu %zu %zu %zu\n", sizeof (*p)[1], sizeof (*mm[0])[1], sizeof fi()[1],
           sizeof fh()->b, sizeof fh()->a);

    /* (*q[N])[M], local */
    float a[4] = {1, 2, 3, 4}, b[4] = {5, 6, 7, 8};
    float (*q[2])[4] = {&a, &b}, x = 1.5f;
    float lm[4][4] = {{0}};
    float (*lr[2])[4][4] = {&lm, &lm};
    (*lr[1])[2][3] = 9.5f;
    printf("%zu %zu %zu %zu %g %g %g %g\n", sizeof q, sizeof q[0], sizeof *q[0],
           sizeof (*lr[1])[2], (*q[1])[2], x, lm[2][3], q[0][0][3]);

    /* global, and the typedef spelling as a member */
    struct S s = {1, {&ga, &gb}};
    (*gr[1])[2][3] = 9.5f;
    gz[2] = &gb;
    printf("%zu %zu %zu %zu %g %g\n", sizeof gq, sizeof gq[0], sizeof *gq[0], sizeof (*gr[1])[2], (*gq[1])[2], gx);
    printf("%g %g %zu %zu %g %g\n", gm[2][3], gq[0][0][3], sizeof gu, sizeof gz, (*gz[2])[1], (*gu[1])[0]);
    printf("%zu %g %zu\n", sizeof s, (*s.rows[1])[3], sizeof *s.rows[0]);

    /* block-scope prototypes, with and without extern, and a mixed declaration */
    {
        extern int twice(int);
        int seven(void), y = 3;
        sum = twice(y) + seven();
        printf("proto %d\n", sum);
    }
    return 0;
}
int twice(int v) { return v * 2; }
int seven(void) { return 7; }
