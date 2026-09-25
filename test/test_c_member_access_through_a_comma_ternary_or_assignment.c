/* Member access and subscripts on a pointer that comes out of a comma, a
 * conditional or an assignment.
 *
 * stb_ds's shget is `((void) stbds_shgeti(t,k), &(t)[temp])->value`, and pxx
 * printed garbage for it: the C type queries (CNodeIsPointer, CNodePtrElemRec,
 * IRPointerStride, ResolveNodeRec's index arm, ...) had no AN_COMMA case, so
 * the comma's result had no pointed-at record and `->value` was read at offset
 * 0 (the `key` pointer). `(i, p)[2]` also used the wrong stride. Subscripting a
 * conditional or an assignment had the same hole in the index arm.
 *
 * `value` sits at a NONZERO offset on purpose: `key` is at offset 0, and a
 * field there reads right even when no record was found. Expected is gcc's
 * output. */
#include <stdio.h>

struct kv { char *key; int value; };
struct kv a[3] = {{"a", 1}, {"b", 2}, {"c", 3}};
int arr[3] = {10, 20, 30};

static int geti(struct kv *t, int k) { (void)t; return k; }
#define shget(t, k) ((void) geti(t, k), &(t)[tmp])->value

int main(void)
{
    struct kv *t = a, *p = a, *q = a + 1;
    int *ip = arr;
    int i = 1, c = 1, tmp = 2;

    printf("%d %d %d\n", ((void)0, &t[i])->value, (0, t[i]).value, (*(0, &t[i])).value);
    printf("%d %d %d\n", (i, ip)[2], (i, t)[1].value, ((i, t) + 1)->value);
    printf("%d %d\n", (0, (1, &t[i]))->value, (0, a)[2].value);
    printf("%d\n", ({ int z = 1; &t[z + 1]; })->value);
    printf("%d\n", (c ? p : q)[1].value);
    printf("%d\n", (c ? p : q)->value);
    printf("%d\n", ((struct kv *)(0, t))[2].value);
    printf("%d\n", shget(t, 5));
    printf("%s\n", ((void)0, &t[0])->key);
    ((void)0, &t[0])->value = 7;
    printf("%d\n", a[0].value);
    printf("%d\n", (p = q)[1].value);
    printf("%d\n", (p = q)->value);
    return 0;
}
