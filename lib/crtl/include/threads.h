/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: C11 <threads.h>, a thin layer over crtl's <pthread.h>, as musl
 * builds it. thrd_create goes through pthread_create, so every thread gets
 * pxx's start trampoline and its own thread-local block. Without this header
 * a pxx C program included the host's <threads.h> and called glibc's
 * thrd_create, whose threads all shared the creator's __thread variables
 * (bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there).
 *
 * Like <pthread.h> it needs --threadsafe. The constants are glibc's values.
 * mtx_timedlock polls mtx_trylock against the deadline (1 ms steps); crtl's
 * mutex has no timed wait of its own yet.
 */
#ifndef _PXX_THREADS_H
#define _PXX_THREADS_H

#include <pthread.h>
#include <time.h>

#if !defined(__cplusplus) && (!defined(__STDC_VERSION__) || __STDC_VERSION__ < 202311L)
#define thread_local _Thread_local
#endif

#define TSS_DTOR_ITERATIONS 4

typedef pthread_t thrd_t;
typedef int (*thrd_start_t)(void *);
typedef pthread_mutex_t mtx_t;
typedef pthread_cond_t cnd_t;
typedef pthread_key_t tss_t;
typedef void (*tss_dtor_t)(void *);
typedef pthread_once_t once_flag;
#define ONCE_FLAG_INIT PTHREAD_ONCE_INIT

enum { thrd_success = 0, thrd_busy = 1, thrd_error = 2, thrd_nomem = 3, thrd_timedout = 4 };
enum { mtx_plain = 0, mtx_recursive = 1, mtx_timed = 2 };

int thrd_create(thrd_t *thr, thrd_start_t func, void *arg);
int thrd_equal(thrd_t a, thrd_t b);
thrd_t thrd_current(void);
int thrd_sleep(const struct timespec *duration, struct timespec *remaining);
void thrd_yield(void);
void thrd_exit(int res) __attribute__((__noreturn__));
int thrd_detach(thrd_t thr);
int thrd_join(thrd_t thr, int *res);

int mtx_init(mtx_t *m, int type);
int mtx_lock(mtx_t *m);
int mtx_timedlock(mtx_t *m, const struct timespec *ts);
int mtx_trylock(mtx_t *m);
int mtx_unlock(mtx_t *m);
void mtx_destroy(mtx_t *m);

void call_once(once_flag *flag, void (*func)(void));

int cnd_init(cnd_t *c);
int cnd_signal(cnd_t *c);
int cnd_broadcast(cnd_t *c);
int cnd_wait(cnd_t *c, mtx_t *m);
int cnd_timedwait(cnd_t *c, mtx_t *m, const struct timespec *ts);
void cnd_destroy(cnd_t *c);

int tss_create(tss_t *key, tss_dtor_t dtor);
void *tss_get(tss_t key);
int tss_set(tss_t key, void *val);
void tss_delete(tss_t key);

#endif /* _PXX_THREADS_H */
