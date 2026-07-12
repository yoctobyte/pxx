/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: pthread — libc-free POSIX threads subset, bridged to the PXX PAL
 * (lib/rtl/palthread clone/futex + lib/rtl/palsync Drepper mutex) via
 * lib/rtl/palpthread.pas. Project-owned; the SAME thread layer as native Pascal
 * TThread (meta-multithreading: one PAL, two consumers).
 *
 * Surface = what the corpus actually uses: mutex, self/equal, create/join
 * (SQLite), plus pthread_once + condition variables (QuickJS js_once/js_cond,
 * feature-c-corpus-quickjs) over palsync's RunOnce + seq-futex condvar. No TLS
 * keys, no cancellation, no scheduler attributes; not a glibc libpthread ABI
 * clone.
 *
 * Requires --threadsafe (x86-64/i386): create/join lower onto __pxxclone, which
 * the compiler rejects without the thread-safe heap/ARC/I-O runtime.
 */
#ifndef _PXX_PTHREAD_H
#define _PXX_PTHREAD_H

#include <time.h>   /* struct timespec for pthread_cond_timedwait */

/* Thread identity = the kernel tid; copyable by value, compared with ==. */
typedef long pthread_t;

/* pthread_mutex_t is a single futex word, laid out to match palsync's
 * TMutex (record State: Integer). Zeroed == free, so a {0} static initialiser
 * and MallocZero both yield a valid unlocked mutex. */
typedef struct { int __state; } pthread_mutex_t;
#define PTHREAD_MUTEX_INITIALIZER { 0 }

/* Attributes are accepted and ignored (the homegrown recursive-mutex path never
 * compiles the settype call; kept so any config still parses/links). */
typedef struct { int __unused; } pthread_mutexattr_t;
typedef struct { int __unused; } pthread_attr_t;
#define PTHREAD_MUTEX_RECURSIVE 1

int  pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *attr);
int  pthread_mutex_destroy(pthread_mutex_t *m);
int  pthread_mutex_lock(pthread_mutex_t *m);
int  pthread_mutex_trylock(pthread_mutex_t *m);
int  pthread_mutex_unlock(pthread_mutex_t *m);

int  pthread_mutexattr_init(pthread_mutexattr_t *a);
int  pthread_mutexattr_destroy(pthread_mutexattr_t *a);
int  pthread_mutexattr_settype(pthread_mutexattr_t *a, int type);

/* One-time initialisation (palsync RunOnce; glibc-compatible int guard). */
typedef int pthread_once_t;
#define PTHREAD_ONCE_INIT 0
int pthread_once(pthread_once_t *guard, void (*init_routine)(void));

/* Condition variable — palsync's seq-futex condvar (first word = the futex
 * generation counter). Zeroed == valid, so {0} static init works. The clock
 * attribute is accepted and ignored: timedwait measures a RELATIVE budget on
 * the monotonic clock, which is what CLOCK_MONOTONIC callers (QuickJS) want;
 * CLOCK_REALTIME absolute deadlines are approximated the same way. */
typedef struct { int __seq; } pthread_cond_t;
#define PTHREAD_COND_INITIALIZER { 0 }
typedef struct { int __clock; } pthread_condattr_t;

int pthread_condattr_init(pthread_condattr_t *a);
int pthread_condattr_destroy(pthread_condattr_t *a);
int pthread_condattr_setclock(pthread_condattr_t *a, int clock_id);

int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *attr);
int pthread_cond_destroy(pthread_cond_t *c);
int pthread_cond_signal(pthread_cond_t *c);
int pthread_cond_broadcast(pthread_cond_t *c);
int pthread_cond_wait(pthread_cond_t *c, pthread_mutex_t *m);
int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m,
                           const struct timespec *abstime);

pthread_t pthread_self(void);
int  pthread_equal(pthread_t a, pthread_t b);

int  pthread_create(pthread_t *t, const pthread_attr_t *attr,
                    void *(*start)(void *), void *arg);
int  pthread_join(pthread_t t, void **retval);

#endif /* _PXX_PTHREAD_H */
