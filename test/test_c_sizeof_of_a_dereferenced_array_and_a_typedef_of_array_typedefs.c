/* Three sizeof defects from real C libraries, one row each, against gcc.

   1. `sizeof *a` of a MULTIDIMENSIONAL array answered the pointer size (8)
      while `sizeof a[0]`, the other spelling of the same object, was right.
      `n = sizeof a / sizeof *a` then overran -- tiny-regex-c's test1
      segfaulted on it. Both the bare and the parenthesised spelling, and
      two stars into a 3-D array.
   2. A typedef of an array of a typedef'd array lost the inner dimension:
      cglm's `typedef vec4 mat4[4]` over `typedef float vec4[4]` was 16 bytes
      (gcc 64), every element read 0, and a LOCAL mat4 with an initializer was
      refused ("expected C expression", glm_mat4_identity). A bracket-less
      alias of vec4 lost its [4] the same way.
   3. `sizeof (t)->key` was refused with "expected ')'" (stb_ds's shput).

   Every expected value differs from the pointer size and from the element
   size, so a row cannot pass by a default. */
#include <stdio.h>

typedef float vec4[4];
typedef vec4 v4alias;
typedef vec4 mat4[4];
typedef int row3[3];
typedef row3 grid[2][5];

char *t[][4] = {{0, 0, 0, 0}, {0, 0, 0, 0}};
int c[][3] = {{1, 2, 3}};
double d3[2][3][4];
v4alias al = {1, 2, 3, 4};
mat4 g = {{1, 2, 3, 4}, {5, 6, 7, 8}, {9, 10, 11, 12}, {13, 14, 15, 16}};
grid gr;

struct kv { double key; char val[20]; };
struct kv arr[3];

int main(void)
{
    mat4 loc = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
    struct kv *p = arr;
    gr[1][4][2] = 77;
    printf("%d %d %d %d %d %d\n", (int)sizeof *t, (int)sizeof(*t), (int)sizeof *c,
           (int)(sizeof t / sizeof *t), (int)sizeof **d3, (int)sizeof *d3);
    printf("%d %d %d %d %d %d\n", (int)sizeof al, (int)sizeof g, (int)sizeof *g,
           (int)sizeof gr, (int)sizeof loc, (int)(sizeof g / sizeof *g));
    printf("%g %g %g %g %d\n", al[3], g[3][3], g[1][2], loc[2][2], gr[1][4][2]);
    printf("%d %d %d\n", (int)sizeof (p)->key, (int)sizeof (p)->val, (int)sizeof (arr)[1].val);
    return 0;
}
