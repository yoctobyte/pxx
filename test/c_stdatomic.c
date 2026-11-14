/* <stdatomic.h> over the gcc builtins: the atomic_* typedefs and macros, the
   _Atomic qualifier, atomic_flag, and a pointer object. Output equals gcc's.
   feature-c-sync-and-atomic-builtins */
#include <stdatomic.h>
#include <stdio.h>

static atomic_int ai = 10;
static _Atomic unsigned short aus = 65535;
static atomic_llong all = -2;
static atomic_flag fl = ATOMIC_FLAG_INIT;
static atomic_bool ab;

int main(void) {
    int r, e;
    long long q;
    atomic_uintptr_t up;
    int x = 5, y = 6;
    int *_Atomic pp = &x;
    int *old;
    r = atomic_fetch_add(&ai, 5); printf("fadd %d %d\n", r, atomic_load(&ai));
    r = atomic_fetch_sub_explicit(&ai, 20, memory_order_acq_rel); printf("fsub %d %d\n", r, ai);
    printf("neg %d\n", atomic_load_explicit(&ai, memory_order_acquire) < 0);
    atomic_store(&ai, 3);
    r = atomic_exchange(&ai, 4); printf("xchg %d %d\n", r, ai);
    e = 9;
    r = atomic_compare_exchange_strong(&ai, &e, 7); printf("cas %d e %d ai %d\n", r, e, ai);
    r = atomic_compare_exchange_weak_explicit(&ai, &e, 7, memory_order_seq_cst, memory_order_relaxed);
    printf("cas %d e %d ai %d\n", r, e, ai);
    r = atomic_fetch_or(&ai, 8); printf("or %d %d\n", r, ai);
    r = atomic_fetch_and(&ai, 12); printf("and %d %d\n", r, ai);
    r = atomic_fetch_xor(&ai, 5); printf("xor %d %d\n", r, ai);
    r = atomic_fetch_add(&aus, 2); printf("us %d %u\n", r, aus);
    q = atomic_fetch_add(&all, 1); printf("ll %lld %lld\n", q, atomic_load(&all));
    r = atomic_flag_test_and_set(&fl); printf("flag %d", r);
    r = atomic_flag_test_and_set(&fl); printf(" %d", r);
    atomic_flag_clear(&fl);
    r = atomic_flag_test_and_set_explicit(&fl, memory_order_acquire); printf(" %d\n", r);
    atomic_store(&ab, 1); printf("bool %d\n", atomic_load(&ab));
    atomic_init(&up, 42); printf("init %lu\n", (unsigned long)atomic_load(&up));
    old = atomic_exchange(&pp, &y); printf("ptr %d %d\n", *old, *atomic_load(&pp));
    atomic_thread_fence(memory_order_seq_cst);
    atomic_signal_fence(memory_order_seq_cst);
    printf("lockfree %d %d %d\n", (int)atomic_is_lock_free(&ai), ATOMIC_INT_LOCK_FREE, memory_order_seq_cst);
    return 0;
}
