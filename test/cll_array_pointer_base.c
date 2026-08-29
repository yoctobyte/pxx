/* A `long long` array must be a pointer base in EVERY shape it decays in.

   IRNodePointerBase used to bail on tyInt64, because cparser's decayed-row
   builders borrowed that tag as a "raw bytes, already scaled" sentinel — and
   tyInt64 is equally the honest tag of `long long a[8]`. Each attempt to tell
   the two apart from the node's declaration missed a shape, silently:

     q - p, long long *          answered 0        (the first bail)
     (char*)(m+1)-(char*)m,
       long long m[3][4]         answered 1, not 32
     *(s.v+3), long long v[8]
       reached as a struct FIELD answered 0, not 3

   Indexing was always right — `a[i]` scales itself — so the layout looked fine
   and only the decayed forms were wrong. unsigned long long (a different tag)
   was correct throughout, which is the tell: a sign bit decided a stride.

   refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag
   bug-c-pointer-difference-on-a-long-long-element-type */
#include <stdio.h>

long long m[3][4];
long long a[8];
unsigned long long um[3][4];
struct LS { long long m[3][4]; long long v[8]; } s;

static int fails;
static void chk(const char *what, long long got, long long want)
{
    if (got != want) { printf("FAIL %s: got %lld want %lld\n", what, got, want); fails++; }
}

int main(void)
{
    int i, j;
    long long *p, *q;

    for (i = 0; i < 3; i++)
        for (j = 0; j < 4; j++) { m[i][j] = 10 * i + j; um[i][j] = 10 * i + j; s.m[i][j] = 10 * i + j; }
    for (i = 0; i < 8; i++) { a[i] = i; s.v[i] = i; }

    /* the whole array decays to a pointer to its ROW: 4 * sizeof(long long) */
    chk("2d-row-bytes",   (char *)(m + 1) - (char *)m, 32);
    chk("2d-row-bytes-2", (char *)(m + 2) - (char *)m, 64);
    chk("2d-unsigned",    (char *)(um + 1) - (char *)um, 32);
    chk("2d-field-bytes", (char *)(s.m + 1) - (char *)s.m, 32);

    /* one subscript decays to a pointer to its ELEMENT */
    chk("2d-elem",        *(m[1] + 1), 11);
    chk("2d-field-elem",  *(s.m[1] + 1), 11);
    chk("3d-row-into-p",  (p = m[2], p[3]), 23);
    chk("fld-row-into-p", (q = s.m[2], q[3]), 23);

    /* a 1-D long long array, as an IDENT and as a struct FIELD */
    chk("1d-elem",        *(a + 3), 3);
    chk("1d-bytes",       (char *)(a + 1) - (char *)a, 8);
    chk("1d-field-elem",  *(s.v + 3), 3);
    chk("1d-field-bytes", (char *)(s.v + 1) - (char *)s.v, 8);

    /* pointer DIFFERENCE counts elements, not bytes */
    p = a + 5; q = a;
    chk("diff-ident",     p - q, 5);
    p = s.v + 6; q = s.v + 1;
    chk("diff-field",     p - q, 5);
    chk("diff-addrof",    &m[1][0] - &m[0][0], 4);

    if (fails == 0) printf("ok\n");
    return 42 + fails;
}
