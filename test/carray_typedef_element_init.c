/* Guard: bug-c-typedef-array-element-init.
   An array typedef (`typedef float vec4[4]`) must make a decl of that type a real
   array — `vec4 v` folds to float[4], `vec4 arr[N]` to [N][4] — not a scalar.
   Before the fix ParseCTypedef dropped the `[4]`, so `v` was a scalar float and
   every element read 0. Exits 42 on success. */
#include <stdio.h>

typedef float vec4[4];
vec4 gv = { 10.0f, 20.0f, 30.0f, 40.0f };   /* global array-typedef init */

int main(void)
{
    vec4 v = { 1.0f, 2.0f, 3.0f, 4.0f };     /* local array-typedef init */
    if (v[0] != 1.0f || v[1] != 2.0f || v[2] != 3.0f || v[3] != 4.0f) return 1;
    if (gv[0] != 10.0f || gv[3] != 40.0f) return 2;

    vec4 arr[8];                             /* folds to [8][4] */
    int i, j;
    for (i = 0; i < 8; i++)
        for (j = 0; j < 4; j++)
            arr[i][j] = (float)(i * 10 + j);
    if (arr[0][0] != 0.0f || arr[3][2] != 32.0f || arr[7][3] != 73.0f) return 3;

    vec4 a, b;                               /* multi-declarator: both arrays */
    a[2] = 7.0f; b[2] = 9.0f;
    if (a[2] != 7.0f || b[2] != 9.0f) return 4;

    vec4 rows[2] = {{1,2,3,4},{5,6,7,8}};    /* 2-D float brace init (local) */
    if (rows[0][0] != 1.0f || rows[1][3] != 8.0f) return 5;

    return 42;
}
