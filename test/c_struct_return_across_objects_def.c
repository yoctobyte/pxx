/* Defines the struct-returning functions that
   test/c_struct_return_across_objects_use.c calls from a separate object.
   bug-c-a-struct-return-across-objects-passes-no-hidden-destination */
struct inode { int x; };
struct mount { int y; };
struct path { struct mount *mnt; struct inode *ip; };
struct big { long a, b, c, d; };

struct path mk(struct inode *ip)
{
    struct path p = { 0, ip };
    return p;
}

struct big mkbig(long k)
{
    struct big b = { k, k * 2, k * 3, k * 4 };
    return b;
}
