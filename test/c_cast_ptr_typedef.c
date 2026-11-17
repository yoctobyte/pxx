/* A cast through a POINTER TYPEDEF must keep the pointee struct.
   pxx read `((PD)p)->w` at offset 0 (the first field) and turned
   `((PD)p)->fn(a)` into that first field, with no call at all. Xlib's
   XAllocID is `(*((_XPrivDisplay)(dpy))->resource_alloc)((dpy))`.
   bug-c-cast-through-a-pointer-typedef-loses-the-pointee */
#include <stdio.h>

struct D { int v; int w; unsigned long (*ra)(struct D *); };
typedef struct D *PD;
typedef struct E { long a; char name[8]; struct D *d; } E, *PE;
typedef int *PI;
typedef int (*FN)(int);

static unsigned long ra(struct D *d) { return (unsigned long)(d->v * 100 + d->w); }
static int inc(int x) { return x + 1; }

int main(void)
{
    struct D d = {4, 2, ra};
    void *vp = &d;
    PD pd = &d;
    E e = {7, "xyz", &d};
    void *ep = &e;
    int arr[3] = {7, 8, 9};
    void *ap = arr;
    void *fp = (void *)inc;

    printf("field %d %d\n", ((PD)vp)->v, ((PD)vp)->w);
    printf("call %lu %lu\n", ((PD)vp)->ra(pd), (*((PD)(vp))->ra)((pd)));
    printf("nested %ld %s %d %lu\n", ((PE)ep)->a, ((PE)ep)->name,
           ((PE)ep)->d->w, ((PE)ep)->d->ra(((PE)ep)->d));
    ((PD)vp)->w = 9;
    printf("store %d\n", d.w);
    printf("scalar %d %d\n", ((PI)ap)[2], *((PI)ap + 1));
    printf("fnptr %d\n", ((FN)fp)(41));
    return 0;
}
