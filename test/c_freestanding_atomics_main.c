/* gcc-built driver for c_freestanding_atomics.c: 4 threads x N calls into the
   pxx object at once, then the exact totals. Prints "atomics ok" or the
   first wrong counter. */
#include <pthread.h>
#include <stdio.h>

struct counters {
    long long add;
    int locked;
    _Bool lock;
    unsigned char pad;
    short lo, hi;
    unsigned char b[4];
};
void fs_work(struct counters *c, int id, int n);

#define T 4
#define N 20000
static struct counters c;
static void *run(void *arg) { fs_work(&c, (int)(long)arg, N); return 0; }

int main(void)
{
    pthread_t th[T];
    long i;
    for (i = 0; i < T; i++) pthread_create(&th[i], 0, run, (void *)i);
    for (i = 0; i < T; i++) pthread_join(th[i], 0);
    if (c.add != 3LL * T * N) { printf("add %lld\n", c.add); return 1; }
    if (c.locked != T * N) { printf("locked %d\n", c.locked); return 1; }
    if (c.lock) { printf("lock held\n"); return 1; }
    if (c.lo != (short)(-T * N)) { printf("lo %d\n", c.lo); return 1; }
    if (c.hi != (short)(T * N)) { printf("hi %d\n", c.hi); return 1; }
    for (i = 0; i < T; i++)
        if (c.b[i] != (unsigned char)N) { printf("b%ld %d\n", i, c.b[i]); return 1; }
    if (c.pad) { printf("pad %d\n", c.pad); return 1; }
    printf("atomics ok\n");
    return 0;
}
