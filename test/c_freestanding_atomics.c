/* --emit-obj --freestanding: the gcc atomic builtins carry their own helpers
   (no crtl in a kernel), and they hold under contention. Driven by
   c_freestanding_atomics_main.c (gcc, pthreads): several threads call
   fs_work at once.
   feature-c-sync-and-atomic-builtins */
struct counters {
    long long add;          /* __atomic_fetch_add, 8 bytes */
    int locked;             /* a plain int under a test-and-set spinlock */
    _Bool lock;
    unsigned char pad;
    short lo, hi;           /* 2-byte CAS loops on halves of one word */
    unsigned char b[4];     /* byte adds on one word */
};

void fs_work(struct counters *c, int id, int n)
{
    int i;
    for (i = 0; i < n; i++) {
        short o, nv;
        __atomic_fetch_add(&c->add, 3, __ATOMIC_SEQ_CST);
        while (__atomic_test_and_set(&c->lock, __ATOMIC_ACQUIRE))
            ;
        c->locked = c->locked + 1;
        __atomic_clear(&c->lock, __ATOMIC_RELEASE);
        o = __atomic_load_n(&c->lo, __ATOMIC_RELAXED);
        do nv = (short)(o - 1);
        while (!__atomic_compare_exchange_n(&c->lo, &o, nv, 1, __ATOMIC_SEQ_CST, __ATOMIC_RELAXED));
        __sync_fetch_and_add(&c->hi, 1);
        __sync_add_and_fetch(&c->b[id & 3], 1);
    }
}
