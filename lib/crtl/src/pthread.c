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
extern void      __pxx_pcond_init(void *c);
extern void      __pxx_pcond_signal(void *c);
extern void      __pxx_pcond_broadcast(void *c);
extern void      __pxx_pcond_wait(void *c, void *m);
extern int       __pxx_pcond_timedwait(void *c, void *m, long long ns);
extern void      __pxx_ponce(void *ctl, void (*proc)(void));
extern long long __pxx_pmonotonic_ns(void);

/* ---- mutex ---- */

/* A RECURSIVE mutex is the futex lock plus an owner tid and a depth: the owner
 * re-locking only counts. __owner is written only by the thread holding the
 * lock, so a thread comparing it with its own tid can only match an entry it
 * made itself. */
int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *attr) {
  __pxx_pmutex_init(m);
  m->__type = attr ? attr->__type : PTHREAD_MUTEX_NORMAL;
  m->__owner = 0;
  m->__count = 0;
  return 0;
}
int pthread_mutex_destroy(pthread_mutex_t *m) { (void)m; return 0; }  /* futex: no teardown */

int pthread_mutex_lock(pthread_mutex_t *m) {
  if (m->__type == PTHREAD_MUTEX_RECURSIVE) {
    long self = (long)__pxx_pthread_self();
    if (m->__owner == self) { m->__count++; return 0; }
    __pxx_pmutex_lock(m);
    m->__owner = self;
    m->__count = 1;
    return 0;
  }
  __pxx_pmutex_lock(m);
  return 0;
}
int pthread_mutex_unlock(pthread_mutex_t *m) {
  if (m->__type == PTHREAD_MUTEX_RECURSIVE) {
    if (m->__owner != (long)__pxx_pthread_self()) return 1;   /* EPERM */
    if (--m->__count > 0) return 0;
    m->__owner = 0;
  }
  __pxx_pmutex_unlock(m);
  return 0;
}
int pthread_mutex_trylock(pthread_mutex_t *m) {
  int r;
  if (m->__type == PTHREAD_MUTEX_RECURSIVE) {
    long self = (long)__pxx_pthread_self();
    if (m->__owner == self) { m->__count++; return 0; }
    r = __pxx_pmutex_trylock(m);
    if (r == 0) { m->__owner = self; m->__count = 1; }
    return r;
  }
  return __pxx_pmutex_trylock(m);
}

int pthread_mutexattr_init(pthread_mutexattr_t *a)    { a->__type = PTHREAD_MUTEX_NORMAL; return 0; }
int pthread_mutexattr_destroy(pthread_mutexattr_t *a) { (void)a; return 0; }
int pthread_mutexattr_settype(pthread_mutexattr_t *a, int t) {
  if (t < PTHREAD_MUTEX_NORMAL || t > PTHREAD_MUTEX_ERRORCHECK) return 22;  /* EINVAL */
  a->__type = t;
  return 0;
}

/* ---- once + condition variables (QuickJS js_once/js_cond surface) ---- */

int pthread_once(pthread_once_t *guard, void (*init_routine)(void)) {
  __pxx_ponce(guard, init_routine);
  return 0;
}

int pthread_condattr_init(pthread_condattr_t *a)                { (void)a; return 0; }
int pthread_condattr_destroy(pthread_condattr_t *a)             { (void)a; return 0; }
int pthread_condattr_setclock(pthread_condattr_t *a, int clk)   { (void)a; (void)clk; return 0; }

int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *attr) {
  (void)attr;
  __pxx_pcond_init(c);
  return 0;
}
int pthread_cond_destroy(pthread_cond_t *c)   { (void)c; return 0; }  /* futex: no teardown */
int pthread_cond_signal(pthread_cond_t *c)    { __pxx_pcond_signal(c);    return 0; }
int pthread_cond_broadcast(pthread_cond_t *c) { __pxx_pcond_broadcast(c); return 0; }

/* The wait releases the futex word; a recursive mutex's owner and depth are
 * cleared for the duration (another thread will lock it) and restored after. */
int pthread_cond_wait(pthread_cond_t *c, pthread_mutex_t *m) {
  long owner = m->__owner; int count = m->__count;
  m->__owner = 0;
  __pxx_pcond_wait(c, m);
  m->__owner = owner; m->__count = count;
  return 0;
}

/* POSIX timedwait takes an ABSOLUTE deadline; palsync takes a relative
 * nanosecond budget. Convert against the wall clock the caller measured on —
 * QuickJS arms it with CLOCK_MONOTONIC "now + timeout", so subtracting the
 * matching clock's now gives the intended relative budget. A deadline already
 * in the past degrades to a zero-budget wait (immediate ETIMEDOUT unless
 * signalled). */
int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m,
                           const struct timespec *abstime) {
  /* now from the Pascal PAL (monotonic; ms granularity) — crtl has no
   * clock_gettime body, and calling one would mark it external-against-libc
   * and give the binary a DT_NEEDED (breaking the libc-free contract). */
  long long now_ns = __pxx_pmonotonic_ns();
  long long ns = (long long)abstime->tv_sec * 1000000000LL
               + (long long)abstime->tv_nsec - now_ns;
  if (ns < 0) ns = 0;
  {
    long owner = m->__owner; int count = m->__count, r;
    m->__owner = 0;
    r = __pxx_pcond_timedwait(c, m, ns);
    m->__owner = owner; m->__count = count;
    return r;
  }
}

/* ---- identity ---- */

pthread_t pthread_self(void)                 { return (pthread_t)__pxx_pthread_self(); }
int pthread_equal(pthread_t a, pthread_t b)  { return a == b; }

/* ---- create / join (tid -> handle registry) ---- */

#define PXX_PTHREAD_MAX 64
#define PXX_HANDLE_BYTES 128         /* TThreadHandle is 64B since the pthread route added PthreadId/EntryFn/EntryArg and StartWord (was 32B); slack for safety. If it ever outgrows this the C side silently scribbles past the slot -- grow this with the record. */

struct pxx_thr_slot {
  long long      tid;                /* > 0 when live */
  int            used;
  unsigned char  h[PXX_HANDLE_BYTES];
  void        *(*start)(void *);     /* the caller's start routine and arg, */
  void          *arg;                /* run by pxx_thr_trampoline, which    */
  void          *ret;                /* keeps the return value for join     */
};
static struct pxx_thr_slot pxx_thr_reg[PXX_PTHREAD_MAX];
static pthread_mutex_t pxx_thr_reg_lock = PTHREAD_MUTEX_INITIALIZER;

/* The thread the PAL spawns runs THIS, not the caller's routine directly: the
 * PAL discards the entry's return value, and POSIX hands it to pthread_join.
 * The slot stays owned by this thread until join frees it, so the store needs
 * no lock; join reads it only after __pxx_pthread_join has seen the thread
 * exit. */
static void *pxx_thr_trampoline(void *p) {
  struct pxx_thr_slot *s = (struct pxx_thr_slot *)p;
  s->ret = s->start(s->arg);
  return s->ret;
}

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
  pxx_thr_reg[slot].start = start;
  pxx_thr_reg[slot].arg   = arg;
  pxx_thr_reg[slot].ret   = 0;
  tid = __pxx_pthread_create(pxx_thr_reg[slot].h, pxx_thr_trampoline, &pxx_thr_reg[slot]);
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
  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  for (i = 0; i < PXX_PTHREAD_MAX; i++) {
    if (pxx_thr_reg[i].used && pxx_thr_reg[i].tid == (long long)t) { slot = i; break; }
  }
  __pxx_pmutex_unlock(&pxx_thr_reg_lock);
  if (slot < 0) return 3;                  /* ESRCH */

  __pxx_pthread_join(pxx_thr_reg[slot].h); /* blocks on the child-tid futex */
  if (retval) *retval = pxx_thr_reg[slot].ret;

  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  pxx_thr_reg[slot].used = 0;
  pxx_thr_reg[slot].tid  = 0;
  __pxx_pmutex_unlock(&pxx_thr_reg_lock);
  return 0;
}
