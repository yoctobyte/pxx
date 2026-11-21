/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: C11 threads over crtl's pthreads (see include/threads.h).
 * The pthread error numbers map to the C11 results as glibc maps them:
 * 0 is thrd_success, ENOMEM thrd_nomem, EBUSY thrd_busy, ETIMEDOUT
 * thrd_timedout, anything else thrd_error.
 */
#include <threads.h>
#include <errno.h>
#include <sched.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

static int crtl_thrd_map(int e)
{
  switch (e) {
  case 0: return thrd_success;
  case ENOMEM: return thrd_nomem;
  case EBUSY: return thrd_busy;
  case ETIMEDOUT: return thrd_timedout;
  default: return thrd_error;
  }
}

/* The start routine returns int; pthread's returns void *. The int rides in
   the pointer, which is also how glibc's thrd_join reads it back. */
struct crtl_thrd_start { thrd_start_t fn; void *arg; };

static void *crtl_thrd_trampoline(void *p)
{
  struct crtl_thrd_start s = *(struct crtl_thrd_start *)p;
  free(p);
  return (void *)(intptr_t)s.fn(s.arg);
}

int thrd_create(thrd_t *thr, thrd_start_t func, void *arg)
{
  struct crtl_thrd_start *s = malloc(sizeof *s);
  int e;
  if (!s) return thrd_nomem;
  s->fn = func;
  s->arg = arg;
  e = pthread_create(thr, 0, crtl_thrd_trampoline, s);
  if (e) free(s);
  return crtl_thrd_map(e);
}

int thrd_equal(thrd_t a, thrd_t b) { return pthread_equal(a, b); }
thrd_t thrd_current(void) { return pthread_self(); }
void thrd_yield(void) { sched_yield(); }

/* 0 slept the whole time, -1 interrupted by a signal, other negative values
   another failure (C11 7.26.5.7). */
int thrd_sleep(const struct timespec *duration, struct timespec *remaining)
{
  if (nanosleep(duration, remaining) == 0) return 0;
  return errno == EINTR ? -1 : -2;
}

void thrd_exit(int res) { pthread_exit((void *)(intptr_t)res); }
int thrd_detach(thrd_t thr) { return crtl_thrd_map(pthread_detach(thr)); }

int thrd_join(thrd_t thr, int *res)
{
  void *r;
  int e = pthread_join(thr, &r);
  if (e) return crtl_thrd_map(e);
  if (res) *res = (int)(intptr_t)r;
  return thrd_success;
}

int mtx_init(mtx_t *m, int type)
{
  pthread_mutexattr_t a;
  int e;
  pthread_mutexattr_init(&a);
  if (type & mtx_recursive) pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
  e = pthread_mutex_init(m, &a);
  pthread_mutexattr_destroy(&a);
  return e ? thrd_error : thrd_success;
}

int mtx_lock(mtx_t *m) { return crtl_thrd_map(pthread_mutex_lock(m)); }
int mtx_trylock(mtx_t *m) { return crtl_thrd_map(pthread_mutex_trylock(m)); }
int mtx_unlock(mtx_t *m) { return crtl_thrd_map(pthread_mutex_unlock(m)); }
void mtx_destroy(mtx_t *m) { pthread_mutex_destroy(m); }

/* ts is an absolute TIME_UTC deadline */
int mtx_timedlock(mtx_t *m, const struct timespec *ts)
{
  struct timespec now, step;
  step.tv_sec = 0;
  step.tv_nsec = 1000000;
  for (;;) {
    int e = pthread_mutex_trylock(m);
    if (e != EBUSY) return crtl_thrd_map(e);
    clock_gettime(CLOCK_REALTIME, &now);
    if (now.tv_sec > ts->tv_sec || (now.tv_sec == ts->tv_sec && now.tv_nsec >= ts->tv_nsec))
      return thrd_timedout;
    nanosleep(&step, 0);
  }
}

void call_once(once_flag *flag, void (*func)(void)) { pthread_once(flag, func); }

int cnd_init(cnd_t *c) { return pthread_cond_init(c, 0) ? thrd_error : thrd_success; }
int cnd_signal(cnd_t *c) { return crtl_thrd_map(pthread_cond_signal(c)); }
int cnd_broadcast(cnd_t *c) { return crtl_thrd_map(pthread_cond_broadcast(c)); }
int cnd_wait(cnd_t *c, mtx_t *m) { return crtl_thrd_map(pthread_cond_wait(c, m)); }
int cnd_timedwait(cnd_t *c, mtx_t *m, const struct timespec *ts)
{
  return crtl_thrd_map(pthread_cond_timedwait(c, m, ts));
}
void cnd_destroy(cnd_t *c) { pthread_cond_destroy(c); }

int tss_create(tss_t *key, tss_dtor_t dtor)
{
  return pthread_key_create(key, dtor) ? thrd_error : thrd_success;
}
void *tss_get(tss_t key) { return pthread_getspecific(key); }
int tss_set(tss_t key, void *val) { return pthread_setspecific(key, val) ? thrd_error : thrd_success; }
void tss_delete(tss_t key) { pthread_key_delete(key); }
