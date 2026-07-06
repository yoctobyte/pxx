/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: pthread — libc-free POSIX threads subset, bridged to the PXX PAL
 * (lib/rtl/palthread clone/futex + lib/rtl/palsync Drepper mutex) via
 * lib/rtl/palpthread.pas. Project-owned; the SAME thread layer as native Pascal
 * TThread (meta-multithreading: one PAL, two consumers).
 *
 * Surface = exactly what SQLite (SQLITE_THREADSAFE=1, HOMEGROWN recursive mutex)
 * uses, plus create/join for real worker-thread tests: mutex, self/equal,
 * create/join. No condition variables, no TLS keys, no cancellation, no
 * scheduler attributes — SQLite references none of them under the homegrown
 * recursive-mutex config, and this is not a glibc libpthread ABI clone.
 *
 * Requires --threadsafe (x86-64/i386): create/join lower onto __pxxclone, which
 * the compiler rejects without the thread-safe heap/ARC/I-O runtime.
 */
#ifndef _PXX_PTHREAD_H
#define _PXX_PTHREAD_H

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

pthread_t pthread_self(void);
int  pthread_equal(pthread_t a, pthread_t b);

int  pthread_create(pthread_t *t, const pthread_attr_t *attr,
                    void *(*start)(void *), void *arg);
int  pthread_join(pthread_t t, void **retval);

#endif /* _PXX_PTHREAD_H */
