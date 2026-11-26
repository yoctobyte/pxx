/* A prototype names a struct type by value BEFORE the struct's body, as
   zstd.h / zstdmt_compress.h / zstd_compress_internal.h do
   (ZSTDMT_initCStream_internal's ZSTD_CCtx_params, 216 bytes, and
   ZSTDMT_createCCtx_advanced's 24-byte ZSTD_customMem). The call is compiled
   from the prototype, so its by-value decision must be the completed struct's:
   pxx passed a POINTER, the callee read the bytes, and every multithreaded
   zstd compression failed with "Parameter is out of bound".
   bug-c-a-struct-parameter-declared-before-its-body-is-passed-as-a-pointer */
#include <stdio.h>

typedef struct big_s Big;          /* memory class: on the stack */
typedef struct mem_s Mem;          /* 24 bytes: memory class too */
typedef struct two_s Two;          /* 16 bytes: two registers */

unsigned long long cal(void *m, const void *d, unsigned long ds, int t, const void *cd,
                       Big p, unsigned long long pl);
void *mk(unsigned n, Mem cm, void *pool);
long pair(Two a, int k, Two b);

struct big_s { int fmt; int wl; long pad[24]; int nb; };
struct mem_s { void *a, *b, *c; };
struct two_s { long x; int y; };

int main(void)
{
    Big b = { 1, 22, { 0 }, 2 };
    Mem m = { (void *)1, (void *)2, (void *)3 };
    Two t1 = { 40, 2 }, t2 = { 500, 7 };
    b.pad[23] = 2323;
    mk(4, m, (void *)5);
    cal((void *)0x10, 0, 30, 4, 0, b, 0xFFFFFFFFFFFFFFFFULL);
    printf("pair %ld\n", pair(t1, 1000, t2));
    return 0;
}

unsigned long long cal(void *m, const void *d, unsigned long ds, int t, const void *cd,
                       Big p, unsigned long long pl)
{
    (void)d; (void)cd;
    printf("cal: m=%p ds=%lu t=%d fmt=%d wl=%d pad23=%ld nb=%d pl=%llu\n",
           m, ds, t, p.fmt, p.wl, p.pad[23], p.nb, pl);
    return 0;
}

void *mk(unsigned n, Mem cm, void *pool)
{
    printf("mk: n=%u a=%p b=%p c=%p pool=%p\n", n, cm.a, cm.b, cm.c, pool);
    return 0;
}

long pair(Two a, int k, Two b)
{
    return a.x + a.y + k + b.x + b.y;
}
