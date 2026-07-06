/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: pthread — libc-free bridge to the PXX PAL. See pthread.h.
 *
 * Mutex + self/equal are 1:1 forwards to the Pascal bridge (palpthread.pas over
 * palsync/palthread). create/join need the 32-byte TThreadHandle preserved from
 * spawn to join, but POSIX pthread_create hands back only a pthread_t (the tid),
 * so this file keeps a small tid->handle registry. The handle bytes stay OPAQUE
 * to C — Pascal writes them in create and reads them in join — so the Pascal
 * record vs C struct layout never has to match.
 */

/* Pascal bridge (lib/rtl/palpthread.pas), bound case-insensitively by name. */
extern void      __pxx_pmutex_init(void *m);
extern void      __pxx_pmutex_lock(void *m);
extern void      __pxx_pmutex_unlock(void *m);
extern int       __pxx_pmutex_trylock(void *m);       /* 0 = acquired, 16 = EBUSY */
extern long long __pxx_pthread_self(void);
extern long long __pxx_pthread_create(void *h, void *(*start)(void *), void *arg);
extern void      __pxx_pthread_join(void *h);

/* ---- mutex ---- */

int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *attr) {
  (void)attr;
  __pxx_pmutex_init(m);
  return 0;
}
int pthread_mutex_destroy(pthread_mutex_t *m) { (void)m; return 0; }  /* futex: no teardown */

int pthread_mutex_lock(pthread_mutex_t *m)    { __pxx_pmutex_lock(m);   return 0; }
int pthread_mutex_unlock(pthread_mutex_t *m)  { __pxx_pmutex_unlock(m); return 0; }
int pthread_mutex_trylock(pthread_mutex_t *m) { return __pxx_pmutex_trylock(m); }

/* Attributes are ignored (homegrown recursive mutex never calls settype). */
int pthread_mutexattr_init(pthread_mutexattr_t *a)            { (void)a; return 0; }
int pthread_mutexattr_destroy(pthread_mutexattr_t *a)         { (void)a; return 0; }
int pthread_mutexattr_settype(pthread_mutexattr_t *a, int t)  { (void)a; (void)t; return 0; }

/* ---- identity ---- */

pthread_t pthread_self(void)                 { return (pthread_t)__pxx_pthread_self(); }
int pthread_equal(pthread_t a, pthread_t b)  { return a == b; }

/* ---- create / join (tid -> handle registry) ---- */

#define PXX_PTHREAD_MAX 64
#define PXX_HANDLE_BYTES 64          /* TThreadHandle is 32B; slack for safety */

struct pxx_thr_slot {
  long long      tid;                /* > 0 when live */
  int            used;
  unsigned char  h[PXX_HANDLE_BYTES];
};
static struct pxx_thr_slot pxx_thr_reg[PXX_PTHREAD_MAX];
static pthread_mutex_t pxx_thr_reg_lock = PTHREAD_MUTEX_INITIALIZER;

int pthread_create(pthread_t *t, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg) {
  int i, slot = -1;
  long long tid;
  (void)attr;

  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  for (i = 0; i < PXX_PTHREAD_MAX; i++) {
    if (!pxx_thr_reg[i].used) { slot = i; pxx_thr_reg[i].used = 1; break; }
  }
  if (slot < 0) { __pxx_pmutex_unlock(&pxx_thr_reg_lock); return 11; }  /* EAGAIN */

  /* Spawn under the registry lock: PalThreadCreate fills the handle bytes and
     returns the child tid. Serialising spawns is fine for test-scale fan-out. */
  tid = __pxx_pthread_create(pxx_thr_reg[slot].h, start, arg);
  if (tid <= 0) {
    pxx_thr_reg[slot].used = 0;
    __pxx_pmutex_unlock(&pxx_thr_reg_lock);
    return 11;                                                          /* EAGAIN */
  }
  pxx_thr_reg[slot].tid = tid;
  __pxx_pmutex_unlock(&pxx_thr_reg_lock);

  if (t) *t = (pthread_t)tid;
  return 0;
}

int pthread_join(pthread_t t, void **retval) {
  int i, slot = -1;
  if (retval) *retval = 0;                 /* thread return value is not tracked */

  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  for (i = 0; i < PXX_PTHREAD_MAX; i++) {
    if (pxx_thr_reg[i].used && pxx_thr_reg[i].tid == (long long)t) { slot = i; break; }
  }
  __pxx_pmutex_unlock(&pxx_thr_reg_lock);
  if (slot < 0) return 3;                  /* ESRCH */

  __pxx_pthread_join(pxx_thr_reg[slot].h); /* blocks on the child-tid futex */

  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  pxx_thr_reg[slot].used = 0;
  pxx_thr_reg[slot].tid  = 0;
  __pxx_pmutex_unlock(&pxx_thr_reg_lock);
  return 0;
}
