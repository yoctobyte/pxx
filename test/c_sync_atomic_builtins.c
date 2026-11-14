/* gcc's __sync_* and __atomic_* builtins at 1, 2, 4 and 8 bytes: return
 * values (old vs new), signed results, a failed compare-exchange writing back
 * `expected`, the pointer-argument forms, a pointer-typed object, a byte
 * atomic beside its neighbours, and the fences. Each call is its own
 * statement (printf's argument order is unspecified). Output equals gcc's.
 * feature-c-sync-and-atomic-builtins */
#include <stdio.h>

struct node { int v; struct node *next; };

static signed char sc = -3;
static unsigned short us = 65530;
static short ss = -7;
static int si = -5;
static unsigned int ui = 7;
static long long sll = -1;
static unsigned long long ull = 0xF0F0F0F0F0F0F0F0ULL;
static _Bool flag;
static unsigned char guard_c[4] = { 0x11, 0x22, 0x33, 0x44 };


int main(void) {
    int r;
    long long a, b;
    /* __sync fetch-and-op / op-and-fetch; signed results stay signed */
    r = __sync_fetch_and_add(&si, 3); printf("fadd %d si %d\n", r, si);
    r = __sync_add_and_fetch(&si, 3); printf("addf %d\n", r);
    r = __sync_fetch_and_sub(&si, 10); printf("fsub %d\n", r);
    printf("neg %d\n", __sync_sub_and_fetch(&si, 1) < 0);
    printf("lt0 %d\n", __sync_fetch_and_add(&si, 0) < 0);
    r = __sync_fetch_and_add(&sc, 1); printf("sc %d %d\n", r, sc);
    r = __sync_add_and_fetch(&sc, -1); printf("sc %d %d\n", r, sc);
    r = __sync_fetch_and_add(&us, 10); printf("us %d %u\n", r, us);
    r = __sync_sub_and_fetch(&us, 5); printf("us %d\n", r);
    r = __sync_fetch_and_sub(&ss, 1); printf("ss %d %d\n", r, ss);
    r = __sync_fetch_and_or(&ui, 8); printf("or %u %u\n", (unsigned)r, ui);
    r = __sync_and_and_fetch(&ui, 13); printf("and %u\n", (unsigned)r);
    r = __sync_xor_and_fetch(&ui, 1); printf("xor %u\n", (unsigned)r);
    r = __sync_nand_and_fetch(&ui, 6); printf("nand %u\n", (unsigned)r);
    r = __sync_fetch_and_nand(&ui, 6); printf("fnand %u %u\n", (unsigned)r, ui);
    a = __sync_fetch_and_add(&sll, 2); printf("sll %lld %lld\n", a, sll);
    a = __sync_add_and_fetch(&sll, -5); printf("sll %lld\n", a);
    printf("sll neg %d\n", __sync_add_and_fetch(&sll, 0) < 0);
    a = (long long)__sync_fetch_and_xor(&ull, 0xFFULL); printf("ull %llx %llx\n", (unsigned long long)a, ull);
    a = (long long)__sync_or_and_fetch(&ull, 1ULL << 63); printf("ull %llx\n", (unsigned long long)a);
    /* compare and swap */
    ui = 1;
    r = __sync_bool_compare_and_swap(&ui, 99, 5); printf("bcas %d %u\n", r, ui);
    r = __sync_bool_compare_and_swap(&ui, 1, 42); printf("bcas %d %u\n", r, ui);
    r = __sync_val_compare_and_swap(&ui, 1, 2); printf("vcas %u %u\n", (unsigned)r, ui);
    r = __sync_val_compare_and_swap(&ui, 42, 43); printf("vcas %u %u\n", (unsigned)r, ui);
    r = __sync_val_compare_and_swap(&sc, -3, -100); printf("vcas sc %d %d\n", r, sc);
    r = __sync_val_compare_and_swap(&ss, -8, -9); printf("vcas ss %d %d\n", r, ss);
    r = __sync_lock_test_and_set(&si, 77); printf("tas %d %d\n", r, si);
    __sync_lock_release(&si); printf("rel %d\n", si);
    __sync_synchronize();
    /* __atomic _n forms */
    r = __atomic_load_n(&sc, __ATOMIC_SEQ_CST); printf("load sc %d\n", r);
    r = __atomic_load_n(&us, __ATOMIC_ACQUIRE); printf("load us %d\n", r);
    a = __atomic_load_n(&sll, __ATOMIC_RELAXED); printf("load sll %lld\n", a);
    __atomic_store_n(&us, 300, __ATOMIC_RELEASE); printf("store %u\n", us);
    r = __atomic_exchange_n(&us, 65535, __ATOMIC_SEQ_CST); printf("xchg %d %u\n", r, us);
    {
        unsigned int exp = 5;
        int ok = __atomic_compare_exchange_n(&ui, &exp, 9, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
        printf("cx fail %d exp %u ui %u\n", ok, exp, ui);
        ok = __atomic_compare_exchange_n(&ui, &exp, 9, 1, __ATOMIC_SEQ_CST, __ATOMIC_RELAXED);
        printf("cx ok %d exp %u ui %u\n", ok, exp, ui);
    }
    {
        signed char e = 0;
        int ok = __atomic_compare_exchange_n(&sc, &e, 1, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
        printf("cx sc %d e %d\n", ok, e);
    }
    r = __atomic_fetch_add(&si, 5, __ATOMIC_SEQ_CST); printf("fadd %d\n", r);
    r = __atomic_add_fetch(&si, 5, __ATOMIC_SEQ_CST); printf("addf %d\n", r);
    r = __atomic_fetch_sub(&si, 20, __ATOMIC_SEQ_CST); printf("fsub %d\n", r);
    r = __atomic_sub_fetch(&si, 1, __ATOMIC_SEQ_CST); printf("subf %d\n", r);
    ui = 0x5A;
    r = __atomic_fetch_and(&ui, 0x0F, 5); printf("fand %x %x\n", r, ui);
    r = __atomic_or_fetch(&ui, 0x30, 5); printf("orf %x\n", r);
    r = __atomic_fetch_xor(&ui, 0xFF, 5); printf("fxor %x %x\n", r, ui);
    r = __atomic_and_fetch(&ui, 0xF0, 5); printf("andf %x\n", r);
    r = __atomic_fetch_nand(&ui, 0x10, 5); printf("fnand %x %x\n", r, ui);
    r = __atomic_xor_fetch(&ui, 1, 5); printf("xorf %x\n", r);
    r = __atomic_fetch_or(&ui, 2, 5); printf("for %x %x\n", r, ui);
    r = __atomic_nand_fetch(&ui, 3, 5); printf("nandf %x\n", r);
    r = __atomic_sub_fetch(&us, 1, 5); printf("us subf %d\n", r);
    r = __atomic_add_fetch(&us, 2, 5); printf("us wrap %d\n", r);
    a = (long long)__atomic_add_fetch(&ull, 0x10, __ATOMIC_SEQ_CST); printf("ull %llx\n", (unsigned long long)a);
    /* generic pointer forms */
    {
        long long got, val = 1234567890123LL, prev, des = 5;
        __atomic_load(&sll, &got, __ATOMIC_SEQ_CST);
        __atomic_store(&sll, &val, __ATOMIC_SEQ_CST);
        val = 77;
        __atomic_exchange(&sll, &val, &prev, __ATOMIC_SEQ_CST);
        printf("generic %lld %lld %lld\n", got, prev, sll);
        got = 1;
        r = __atomic_compare_exchange(&sll, &got, &des, 0, 5, 5); printf("gcx %d got %lld\n", r, got);
        r = __atomic_compare_exchange(&sll, &got, &des, 0, 5, 5); printf("gcx %d sll %lld\n", r, sll);
    }
    {
        short sv = 12, so;
        __atomic_exchange(&ss, &sv, &so, 5); printf("gx short %d %d\n", so, ss);
    }
    /* test_and_set / clear */
    r = __atomic_test_and_set(&flag, __ATOMIC_SEQ_CST); printf("tas %d\n", r);
    r = __atomic_test_and_set(&flag, __ATOMIC_SEQ_CST); printf("tas %d\n", r);
    __atomic_clear(&flag, __ATOMIC_SEQ_CST); printf("clear %d\n", flag);
    /* a byte atomic in the middle of a word leaves its neighbours alone */
    __atomic_fetch_add(&guard_c[1], 1, __ATOMIC_SEQ_CST);
    __atomic_exchange_n(&guard_c[2], 0x7F, __ATOMIC_SEQ_CST);
    __sync_fetch_and_sub(&guard_c[3], 0x45);
    printf("guard %x %x %x %x\n", guard_c[0], guard_c[1], guard_c[2], guard_c[3]);
    /* a pointer object */
    {
        static struct node na = { 1, 0 }, nb = { 2, 0 };
        struct node *head = 0, *old;
        old = __atomic_exchange_n(&head, &na, __ATOMIC_SEQ_CST);
        printf("ptr %d %d\n", old == 0, head->v);
        nb.next = __atomic_load_n(&head, __ATOMIC_SEQ_CST);
        r = __sync_bool_compare_and_swap(&head, &na, &nb);
        printf("pcas %d %d %d\n", r, head->v, __atomic_load_n(&head, 5)->next->v);
        old = __sync_val_compare_and_swap(&head, &na, &na);
        printf("pvcas %d %d\n", old->v, head->v);
    }
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
    __atomic_signal_fence(__ATOMIC_SEQ_CST);
    a = __atomic_always_lock_free(4, 0);
    b = __atomic_is_lock_free(8, 0);
    printf("lockfree %lld %lld %d\n", a, b, __ATOMIC_SEQ_CST);
    return 0;
}
