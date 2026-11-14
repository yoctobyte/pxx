/* <stdatomic.h> for pxx: C11 atomics over gcc's __atomic builtins, which the
 * C frontend lowers to per-width helpers the translation unit carries itself
 * (hosted and --freestanding alike).
 *
 * Limits, on purpose:
 *  - Every operation is sequentially consistent whatever order is named. The
 *    order arguments are evaluated and ignored, which is correct for every
 *    order; a weaker order is only allowed to be faster.
 *  - _Atomic is accepted as a qualifier and dropped: an atomic object is an
 *    ordinary object of the same size. Access it through these macros; a
 *    plain `x = 1` or `x++` on it is NOT atomic under pxx. The specifier form
 *    `_Atomic(T)` is refused by name.
 *  - Objects of 1, 2, 4 and 8 bytes (8 only on 64-bit targets).
 *
 * feature-c-sync-and-atomic-builtins */
#ifndef _STDATOMIC_H
#define _STDATOMIC_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    memory_order_relaxed = __ATOMIC_RELAXED,
    memory_order_consume = __ATOMIC_CONSUME,
    memory_order_acquire = __ATOMIC_ACQUIRE,
    memory_order_release = __ATOMIC_RELEASE,
    memory_order_acq_rel = __ATOMIC_ACQ_REL,
    memory_order_seq_cst = __ATOMIC_SEQ_CST
} memory_order;

#define ATOMIC_BOOL_LOCK_FREE     2
#define ATOMIC_CHAR_LOCK_FREE     2
#define ATOMIC_CHAR16_T_LOCK_FREE 2
#define ATOMIC_CHAR32_T_LOCK_FREE 2
#define ATOMIC_WCHAR_T_LOCK_FREE  2
#define ATOMIC_SHORT_LOCK_FREE    2
#define ATOMIC_INT_LOCK_FREE      2
#define ATOMIC_LONG_LOCK_FREE     2
#define ATOMIC_LLONG_LOCK_FREE    2
#define ATOMIC_POINTER_LOCK_FREE  2

typedef _Bool              atomic_bool;
typedef char               atomic_char;
typedef signed char        atomic_schar;
typedef unsigned char      atomic_uchar;
typedef short              atomic_short;
typedef unsigned short     atomic_ushort;
typedef int                atomic_int;
typedef unsigned int       atomic_uint;
typedef long               atomic_long;
typedef unsigned long      atomic_ulong;
typedef long long          atomic_llong;
typedef unsigned long long atomic_ullong;
typedef int_least16_t      atomic_int_least16_t;
typedef uint_least16_t     atomic_uint_least16_t;
typedef int_least32_t      atomic_int_least32_t;
typedef uint_least32_t     atomic_uint_least32_t;
typedef int_least64_t      atomic_int_least64_t;
typedef uint_least64_t     atomic_uint_least64_t;
typedef intptr_t           atomic_intptr_t;
typedef uintptr_t          atomic_uintptr_t;
typedef size_t             atomic_size_t;
typedef ptrdiff_t          atomic_ptrdiff_t;
typedef intmax_t           atomic_intmax_t;
typedef uintmax_t          atomic_uintmax_t;

#define ATOMIC_VAR_INIT(v) (v)
#define atomic_init(obj, v) ((void)(*(obj) = (v)))
#define kill_dependency(y) (y)

#define atomic_thread_fence(o) __atomic_thread_fence(o)
#define atomic_signal_fence(o) __atomic_signal_fence(o)
#define atomic_is_lock_free(obj) __atomic_is_lock_free(sizeof(*(obj)), (obj))

#define atomic_store(obj, v)                 __atomic_store_n((obj), (v), __ATOMIC_SEQ_CST)
#define atomic_store_explicit(obj, v, o)     __atomic_store_n((obj), (v), (o))
#define atomic_load(obj)                     __atomic_load_n((obj), __ATOMIC_SEQ_CST)
#define atomic_load_explicit(obj, o)         __atomic_load_n((obj), (o))
#define atomic_exchange(obj, v)              __atomic_exchange_n((obj), (v), __ATOMIC_SEQ_CST)
#define atomic_exchange_explicit(obj, v, o)  __atomic_exchange_n((obj), (v), (o))

#define atomic_compare_exchange_strong(obj, exp, des) \
    __atomic_compare_exchange_n((obj), (exp), (des), 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)
#define atomic_compare_exchange_strong_explicit(obj, exp, des, s, f) \
    __atomic_compare_exchange_n((obj), (exp), (des), 0, (s), (f))
#define atomic_compare_exchange_weak(obj, exp, des) \
    __atomic_compare_exchange_n((obj), (exp), (des), 1, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)
#define atomic_compare_exchange_weak_explicit(obj, exp, des, s, f) \
    __atomic_compare_exchange_n((obj), (exp), (des), 1, (s), (f))

#define atomic_fetch_add(obj, v)              __atomic_fetch_add((obj), (v), __ATOMIC_SEQ_CST)
#define atomic_fetch_add_explicit(obj, v, o)  __atomic_fetch_add((obj), (v), (o))
#define atomic_fetch_sub(obj, v)              __atomic_fetch_sub((obj), (v), __ATOMIC_SEQ_CST)
#define atomic_fetch_sub_explicit(obj, v, o)  __atomic_fetch_sub((obj), (v), (o))
#define atomic_fetch_or(obj, v)               __atomic_fetch_or((obj), (v), __ATOMIC_SEQ_CST)
#define atomic_fetch_or_explicit(obj, v, o)   __atomic_fetch_or((obj), (v), (o))
#define atomic_fetch_xor(obj, v)              __atomic_fetch_xor((obj), (v), __ATOMIC_SEQ_CST)
#define atomic_fetch_xor_explicit(obj, v, o)  __atomic_fetch_xor((obj), (v), (o))
#define atomic_fetch_and(obj, v)              __atomic_fetch_and((obj), (v), __ATOMIC_SEQ_CST)
#define atomic_fetch_and_explicit(obj, v, o)  __atomic_fetch_and((obj), (v), (o))

typedef struct { unsigned char __val; } atomic_flag;
#define ATOMIC_FLAG_INIT { 0 }
#define atomic_flag_test_and_set(f)             __atomic_test_and_set(&(f)->__val, __ATOMIC_SEQ_CST)
#define atomic_flag_test_and_set_explicit(f, o) __atomic_test_and_set(&(f)->__val, (o))
#define atomic_flag_clear(f)                    __atomic_clear(&(f)->__val, __ATOMIC_SEQ_CST)
#define atomic_flag_clear_explicit(f, o)        __atomic_clear(&(f)->__val, (o))

#endif
