/* sizeof of a PARTIAL index answers the ROW, not the element.

   There were two sizeof implementations. The unparenthesised spelling walked a
   type descriptor and knew that one subscript peels one dimension; the
   parenthesised spelling had its own per-shape copy with no multi-dimension
   rule. One parenthesis decided whether

       memcpy(dst[1], src[1], sizeof(src[1]))

   copied a row or a single int -- silently, on a plain global array, with no
   cast and no struct in sight. The `sizeof(a[0])/sizeof(a[0][0])` element count
   answered 1 instead of 4 for the same reason.

   A multidim array reached as a record FIELD had a second defect: the walk
   bailed to the pointer-size default rather than ask RecFieldArrDimSpanAt, so
   `sizeof s.m[0]` answered 8 for int, char and double alike -- a row measured
   as a pointer, and the char row correct only by coincidence.

   bug-c-sizeof-a-partial-index-answers-the-element-not-the-row */
#include <stdio.h>
#include <string.h>

struct Inner { int m[3][4]; };
struct S { int m[3][4]; char c[2][8]; double d[2][3]; int t[2][3][4]; struct Inner in; };
struct S gs;
struct S garr[2];
struct S *gp;

int  gm[3][4];
char gc[2][8];
double gd[2][3];
int  gt[2][3][4];
int  src[3][4], dst[3][4];

static int fails;
static void chk(const char *what, int got, int want)
{
    if (got != want) { printf("FAIL %s: got %d want %d\n", what, got, want); fails++; }
}

int main(void)
{
    int i, j, k;
    for (i = 0; i < 3; i++)
        for (j = 0; j < 4; j++) { src[i][j] = 10 * i + j; gs.m[i][j] = 10 * i + j; dst[i][j] = -1; }
    for (i = 0; i < 2; i++)
        for (j = 0; j < 3; j++)
            for (k = 0; k < 4; k++) gt[i][j][k] = 100 * i + 10 * j + k;
    gp = &gs;

    /* both spellings, one answer */
    chk("bare-ident",   (int)sizeof gm[0],      16);
    chk("paren-ident",  (int)sizeof(gm[0]),     16);
    chk("bare-whole",   (int)sizeof gm,         48);
    chk("paren-whole",  (int)sizeof(gm),        48);
    chk("full-index",   (int)sizeof(gm[0][0]),   4);

    /* element widths: a char row is 8 bytes and so is a pointer, so int and
       double are what actually distinguish "row" from "pointer" here */
    chk("char-row",     (int)sizeof(gc[0]),      8);
    chk("double-row",   (int)sizeof(gd[0]),     24);

    /* three dimensions: one subscript peels one */
    chk("3d-one-sub",   (int)sizeof(gt[0]),     48);
    chk("3d-two-sub",   (int)sizeof(gt[0][0]),  16);
    chk("3d-three-sub", (int)sizeof(gt[0][0][0]), 4);

    /* through a struct field, a pointer, a nested field, an array element */
    chk("field-bare",   (int)sizeof gs.m[0],    16);
    chk("field-paren",  (int)sizeof(gs.m[0]),   16);
    chk("field-char",   (int)sizeof(gs.c[0]),    8);
    chk("field-double", (int)sizeof(gs.d[0]),   24);
    chk("arrow",        (int)sizeof(gp->m[0]),  16);
    chk("nested",       (int)sizeof(gs.in.m[0]),16);
    chk("elem-of-arr",  (int)sizeof(garr[0].m), 48);
    chk("elem-of-arr2", (int)sizeof(garr[0].m[0]), 16);

    /* THE two idioms this cost */
    memcpy(dst[1], src[1], sizeof(src[1]));
    chk("memcpy-row0", dst[1][0], 10);
    chk("memcpy-row1", dst[1][1], 11);
    chk("memcpy-row3", dst[1][3], 13);
    chk("elem-count",  (int)(sizeof(gm[0]) / sizeof(gm[0][0])), 4);
    chk("row-count",   (int)(sizeof(gm) / sizeof(gm[0])),       3);

    if (fails == 0) printf("ok\n");
    return 42 + fails;
}
