/* b191 (feature-c-corpus-tcc): `int nb, *lv;` in a struct — a starred LATER
   declarator over a non-pointer base type. The pointee type fell to unknown,
   so lv[i] loads read 8 bytes and dragged the neighbouring int into the upper
   half; tcc's symbol-version table (int nb_local_ver, *local_ver;) indexed
   sym_versions[2^32] and produced binaries bound to wrong glibc symbol
   versions. Exit 42 = pass. */
#include <stdlib.h>
struct V { int nb, *lv; };
struct S { char *a; char *b; int c; int d; };
static struct S *arr;
static int check(struct V *v) {
    int i, t = 0;
    for (i = 0; i < v->nb; i++)
        if (v->lv[i] > 0)
            t += arr[v->lv[i]].c;
    return t;
}
int main(void) {
    struct V vv;
    int vals[4];
    vals[0] = 1; vals[1] = -1; vals[2] = 0; vals[3] = 1;
    vv.nb = 3; vv.lv = vals;
    arr = calloc(2, sizeof(*arr));
    arr[1].c = 7;
    if (check(&vv) != 7) return 1;
    if (sizeof(struct V) != 16) return 2;
    return 42;
}
