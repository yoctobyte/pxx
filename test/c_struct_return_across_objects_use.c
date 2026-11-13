/* Calls struct-returning functions defined in another object
   (test/c_struct_return_across_objects_def.c). The call goes through the GOT,
   and the caller used to leave r10, the hidden result pointer, unset, so the
   callee wrote through garbage.
   bug-c-a-struct-return-across-objects-passes-no-hidden-destination */
#include <stdio.h>
struct inode { int x; };
struct mount { int y; };
struct path { struct mount *mnt; struct inode *ip; };
struct big { long a, b, c, d; };
struct path mk(struct inode *ip);
struct big mkbig(long k);

static int use(struct path p) { return p.ip ? p.ip->x : -1; }

int main(void)
{
    struct inode i = { 5 };
    struct path a = mk(&i);
    struct big b = mkbig(7);
    printf("var %d %d\n", a.ip->x, a.mnt == 0);
    printf("arg %d\n", use(mk(&i)));
    printf("big %ld %ld %ld %ld\n", b.a, b.b, b.c, b.d);
    printf("field %ld\n", mkbig(3).d);
    return 0;
}
