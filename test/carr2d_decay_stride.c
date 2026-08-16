/* What a multi-dimensional array STEPS BY once it decays to a pointer.

   Two strides, both wrong before this, both silent:

     m + 1     on `int m[3][4]` must step a ROW (16 bytes). pxx stepped 4 —
               the element size — because the decay read Syms[].ElemType and a
               multi-dim array's element type is its scalar.
     m[1] + 1  must step an ELEMENT (4 bytes), because m[1] is `int *`. pxx
               stepped 1: the partial index is built as a raw byte add over a
               base retagged tyInt64, so IRPointerStride found no pointer
               operand to ask and took its size-1 default. `*(m[1]+1)` then
               read one byte past the element and answered 0x05000000 for 5.

   bug-c-a-multidim-array-decays-with-the-element-stride
   bug-c-a-decayed-array-row-steps-one-byte */
#include <stdio.h>
#include <string.h>

int m[3][4];
int t[2][3][4];
char s[2][8] = {"ab", "cd"};

static int fails;
static void chk(const char *what, int got, int want)
{
    if (got != want) { printf("FAIL %s: got %d want %d\n", what, got, want); fails++; }
}

int main(void)
{
    int a[5];
    int *p;
    int (*r)[4];

    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 4; j++) m[i][j] = i * 4 + j;
    for (int i = 0; i < 5; i++) a[i] = i;
    t[1][2][3] = 9;

    /* the whole array decays to a pointer to its ROW */
    chk("m+1-bytes",  (int)((char *)(m + 1) - (char *)m), 16);
    chk("m+2-bytes",  (int)((char *)(m + 2) - (char *)m), 32);
    chk("row-deref",  (*(m + 1))[2], 6);
    r = m + 1;
    chk("row-var",    r[1][3], 11);

    /* one subscript decays to a pointer to its ELEMENT */
    chk("m[1]+1",     *(m[1] + 1), 5);
    chk("m[2]+3",     *(m[2] + 3), 11);
    p = m[1];
    chk("row-into-p", p[1] + *(p + 2), 5 + 6);
    chk("char-row",   strcmp(s[0] + 1, "b"), 0);

    /* a 3-D array's first subscript leaves a 2-D remainder: a row of 4 */
    r = t[1];
    chk("3d-row",     r[2][3], 9);

    /* POINTER DIFFERENCE counts ELEMENTS, and a full index has already spent
       every dimension — so this must not see the row stride the decay uses.
       Answering the row stride here made &g[1][0] - &g[0][0] come out as 1
       (Track T caught it in cstr_table_2d_rows.c one commit later). */
    chk("diff-elems",   (int)(&m[1][0] - &m[0][0]), 4);
    chk("diff-chars",   (int)(&s[1][0] - &s[0][0]), 8);
    chk("diff-within",  (int)(&m[0][3] - &m[0][1]), 2);

    /* one dimension is untouched by any of it */
    chk("1d-plus",    *(a + 3), 3);
    chk("1d-index",   a[1] + 1, 2);

    if (fails == 0) printf("ok\n");
    return 42 + fails;
}
