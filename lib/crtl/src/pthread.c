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

#include <pthread.h>
#include <setjmp.h>   /* pthread_exit unwinds to the thread's trampoline */
#include <stdlib.h>
#include <string.h>
#include <sched.h>
#include <errno.h>    /* ENOMEM from pthread_atfork */
#include <unistd.h>   /* fork() and __crtl_atfork_hook live in unistd.c */
#include <sys/syscall.h>  /* SYS_arch_prctl, for a thread's ELF TLS block */

/* Pascal bridge (lib/rtl/palpthread.pas), bound case-insensitively by name. */
extern void      __pxx_pmutex_init(void *m);
extern void      __pxx_pmutex_lock(void *m);
extern void      __pxx_pmutex_unlock(void *m);
extern int       __pxx_pmutex_trylock(void *m);       /* 0 = acquired, 16 = EBUSY */
extern long long __pxx_pthread_self(void);
extern long long __pxx_pthread_create(void *h, void *(*start)(void *), void *arg);
extern void      __pxx_pthread_join(void *h);
extern int       __pxx_pthread_exited(void *h);
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

/* ---- reader-writer lock (see pthread.h) ---- */

int pthread_rwlock_init(pthread_rwlock_t *rw, const pthread_rwlockattr_t *attr) {
  (void)attr;
  __pxx_pmutex_init(&rw->__lock);
  __pxx_pcond_init(&rw->__seq);
  rw->__readers = 0; rw->__writer = 0; rw->__wwait = 0;
  return 0;
}
int pthread_rwlock_destroy(pthread_rwlock_t *rw) { (void)rw; return 0; }

int pthread_rwlock_rdlock(pthread_rwlock_t *rw) {
  __pxx_pmutex_lock(&rw->__lock);
  while (rw->__writer || rw->__wwait) __pxx_pcond_wait(&rw->__seq, &rw->__lock);
  rw->__readers++;
  __pxx_pmutex_unlock(&rw->__lock);
  return 0;
}
int pthread_rwlock_tryrdlock(pthread_rwlock_t *rw) {
  int r = 16;   /* EBUSY */
  __pxx_pmutex_lock(&rw->__lock);
  if (!rw->__writer && !rw->__wwait) { rw->__readers++; r = 0; }
  __pxx_pmutex_unlock(&rw->__lock);
  return r;
}
int pthread_rwlock_wrlock(pthread_rwlock_t *rw) {
  __pxx_pmutex_lock(&rw->__lock);
  rw->__wwait++;
  while (rw->__writer || rw->__readers) __pxx_pcond_wait(&rw->__seq, &rw->__lock);
  rw->__wwait--;
  rw->__writer = 1;
  __pxx_pmutex_unlock(&rw->__lock);
  return 0;
}
int pthread_rwlock_trywrlock(pthread_rwlock_t *rw) {
  int r = 16;   /* EBUSY */
  __pxx_pmutex_lock(&rw->__lock);
  if (!rw->__writer && !rw->__readers) { rw->__writer = 1; r = 0; }
  __pxx_pmutex_unlock(&rw->__lock);
  return r;
}
/* Whichever kind it held: a writer clears the flag, the last reader leaves.
   Broadcast, since readers and a writer may both be waiting. */
int pthread_rwlock_unlock(pthread_rwlock_t *rw) {
  __pxx_pmutex_lock(&rw->__lock);
  if (rw->__writer) rw->__writer = 0;
  else if (rw->__readers > 0) rw->__readers--;
  __pxx_pcond_broadcast(&rw->__seq);
  __pxx_pmutex_unlock(&rw->__lock);
  return 0;
}
int pthread_rwlockattr_init(pthread_rwlockattr_t *a)    { a->__kind = 0; return 0; }
int pthread_rwlockattr_destroy(pthread_rwlockattr_t *a) { (void)a; return 0; }

/* ---- once + condition variables (QuickJS js_once/js_cond surface) ---- */

/* pthread_atfork: up to 32 handler triples, run by fork() in unistd.c through
   __crtl_atfork_hook. Registration is under no lock: it happens at library
   init in every real caller, before threads exist. ENOMEM past 32, as a
   failed allocation would give. feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools */
#define CRTL_ATFORK_MAX 32
static void (*crtl_af_prepare[CRTL_ATFORK_MAX])(void);
static void (*crtl_af_parent[CRTL_ATFORK_MAX])(void);
static void (*crtl_af_child[CRTL_ATFORK_MAX])(void);
static int crtl_af_count;
extern void (*__crtl_atfork_hook)(int phase);

static void crtl_atfork_run(int phase) {
  int i;
  if (phase == 0) {
    for (i = crtl_af_count - 1; i >= 0; i--)
      if (crtl_af_prepare[i]) crtl_af_prepare[i]();
  } else {
    for (i = 0; i < crtl_af_count; i++) {
      if (phase == 1 && crtl_af_parent[i]) crtl_af_parent[i]();
      if (phase == 2 && crtl_af_child[i]) crtl_af_child[i]();
    }
  }
}

int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void)) {
  if (crtl_af_count >= CRTL_ATFORK_MAX) return ENOMEM;
  crtl_af_prepare[crtl_af_count] = prepare;
  crtl_af_parent[crtl_af_count] = parent;
  crtl_af_child[crtl_af_count] = child;
  crtl_af_count++;
  __crtl_atfork_hook = crtl_atfork_run;
  return 0;
}

int pthread_once(pthread_once_t *guard, void (*init_routine)(void)) {
  __pxx_ponce(guard, init_routine);
  return 0;
}

int pthread_condattr_init(pthread_condattr_t *a)                { a->__clock = CLOCK_REALTIME; return 0; }
int pthread_condattr_destroy(pthread_condattr_t *a)             { (void)a; return 0; }
int pthread_condattr_setclock(pthread_condattr_t *a, int clk) {
  if (clk != CLOCK_REALTIME && clk != CLOCK_MONOTONIC) return EINVAL;
  a->__clock = clk;
  return 0;
}
int pthread_condattr_getclock(const pthread_condattr_t *a, int *clk) { *clk = a->__clock; return 0; }

int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *attr) {
  __pxx_pcond_init(c);
  c->__clock = attr ? attr->__clock : CLOCK_REALTIME;
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
 * nanosecond budget. The deadline is on the cond's own clock: CLOCK_REALTIME
 * unless pthread_condattr_setclock chose another. It was always read as
 * MONOTONIC, which suits QuickJS (it sets CLOCK_MONOTONIC) and made every
 * default cond wait about 56 years for a realtime deadline -- sem_timedwait
 * and C11 cnd_timedwait never timed out. A deadline already in the past
 * degrades to a zero-budget wait (immediate ETIMEDOUT unless signalled). */
int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m,
                           const struct timespec *abstime) {
  struct timespec now;
  long long now_ns, ns;
  if (clock_gettime(c->__clock, &now) != 0) return EINVAL;
  now_ns = (long long)now.tv_sec * 1000000000LL + now.tv_nsec;
  ns = (long long)abstime->tv_sec * 1000000000LL
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
  int            detached;           /* pthread_detach: nobody will join; the
                                        slot is reclaimed once the thread exits */
  unsigned char  h[PXX_HANDLE_BYTES];
  void        *(*start)(void *);     /* the caller's start routine and arg, */
  void          *arg;                /* run by pxx_thr_trampoline, which    */
  void          *ret;                /* keeps the return value for join     */
  jmp_buf        exit_jb;            /* pthread_exit's way back to it       */
  void          *elftls;             /* this thread's ELF TLS block, or 0   */
};
static struct pxx_thr_slot pxx_thr_reg[PXX_PTHREAD_MAX];
static pthread_mutex_t pxx_thr_reg_lock = PTHREAD_MUTEX_INITIALIZER;

/* The thread the PAL spawns runs THIS, not the caller's routine directly: the
 * PAL discards the entry's return value, and POSIX hands it to pthread_join.
 * The slot stays owned by this thread until join frees it, so the store needs
 * no lock; join reads it only after __pxx_pthread_join has seen the thread
 * exit. */
/* ---- thread-specific data ----
 * A key's values live in a __thread array, so every thread has its own and a
 * get is one load. Destructors run when a crtl thread ends, by return or by
 * pthread_exit, up to PTHREAD_DESTRUCTOR_ITERATIONS rounds as POSIX says. */
static void (*pxx_key_dtor[PTHREAD_KEYS_MAX])(void *);
static unsigned char pxx_key_used[PTHREAD_KEYS_MAX];
static __thread void *pxx_key_val[PTHREAD_KEYS_MAX];
static pthread_mutex_t pxx_key_lock = PTHREAD_MUTEX_INITIALIZER;

int pthread_key_create(pthread_key_t *k, void (*destructor)(void *)) {
  int i;
  __pxx_pmutex_lock(&pxx_key_lock);
  for (i = 0; i < PTHREAD_KEYS_MAX; i++)
    if (!pxx_key_used[i]) {
      pxx_key_used[i] = 1;
      pxx_key_dtor[i] = destructor;
      __pxx_pmutex_unlock(&pxx_key_lock);
      pxx_key_val[i] = 0;
      *k = (pthread_key_t)i;
      return 0;
    }
  __pxx_pmutex_unlock(&pxx_key_lock);
  return 11;                                              /* EAGAIN */
}

int pthread_key_delete(pthread_key_t k) {
  if (k >= PTHREAD_KEYS_MAX || !pxx_key_used[k]) return 22;   /* EINVAL */
  __pxx_pmutex_lock(&pxx_key_lock);
  pxx_key_used[k] = 0;
  pxx_key_dtor[k] = 0;
  __pxx_pmutex_unlock(&pxx_key_lock);
  return 0;
}

void *pthread_getspecific(pthread_key_t k) {
  return k < PTHREAD_KEYS_MAX ? pxx_key_val[k] : 0;
}

int pthread_setspecific(pthread_key_t k, const void *v) {
  if (k >= PTHREAD_KEYS_MAX || !pxx_key_used[k]) return 22;   /* EINVAL */
  pxx_key_val[k] = (void *)v;
  return 0;
}

static void pxx_key_run_dtors(void) {
  int round, i, again;
  for (round = 0; round < PTHREAD_DESTRUCTOR_ITERATIONS; round++) {
    again = 0;
    for (i = 0; i < PTHREAD_KEYS_MAX; i++) {
      void *v = pxx_key_val[i];
      void (*d)(void *) = pxx_key_dtor[i];
      if (v && d && pxx_key_used[i]) {
        pxx_key_val[i] = 0;
        d(v);
        again = 1;
      }
    }
    if (!again) break;
  }
}

/* ---- spin locks: one int word ---- */
int pthread_spin_init(pthread_spinlock_t *l, int pshared) { (void)pshared; *l = 0; return 0; }
int pthread_spin_destroy(pthread_spinlock_t *l) { (void)l; return 0; }
int pthread_spin_lock(pthread_spinlock_t *l) {
  while (__sync_lock_test_and_set((int *)l, 1))
    while (*l) { }
  return 0;
}
int pthread_spin_trylock(pthread_spinlock_t *l) {
  return __sync_lock_test_and_set((int *)l, 1) ? 16 : 0;   /* EBUSY */
}
int pthread_spin_unlock(pthread_spinlock_t *l) { __sync_lock_release((int *)l); return 0; }

/* ---- attributes: the detach state is used, the stack size is kept ---- */
int pthread_attr_init(pthread_attr_t *a) {
  memset(a, 0, sizeof *a);
  a->__stacksize = 8UL * 1024 * 1024;
  return 0;
}
int pthread_attr_destroy(pthread_attr_t *a) { (void)a; return 0; }
int pthread_attr_setdetachstate(pthread_attr_t *a, int st) {
  if (st != PTHREAD_CREATE_JOINABLE && st != PTHREAD_CREATE_DETACHED) return 22;
  a->__detach = st;
  return 0;
}
int pthread_attr_getdetachstate(const pthread_attr_t *a, int *st) { *st = a->__detach; return 0; }
int pthread_attr_setstacksize(pthread_attr_t *a, unsigned long size) {
  if (size < PTHREAD_STACK_MIN) return 22;
  a->__stacksize = size;
  return 0;
}
int pthread_attr_getstacksize(const pthread_attr_t *a, unsigned long *size) {
  *size = a->__stacksize;
  return 0;
}

/* A name is advice; this runtime keeps none. */
int pthread_setname_np(pthread_t t, const char *name) { (void)t; (void)name; return 0; }
int pthread_getname_np(pthread_t t, char *name, unsigned long len) {
  (void)t;
  if (len) name[0] = 0;
  return 0;
}

/* The running crtl thread's slot, for pthread_exit; 0 on the main thread and
 * on threads crtl did not start. */
static __thread struct pxx_thr_slot *pxx_thr_cur;

/* ---- ELF thread-local storage (x86-64) ----
 * A `__thread` in an object compiled with --system-libs is real ELF TLS,
 * reached through fs. When pxx --link links such an object, it lays the
 * `.tdata` inputs out as a TLS template, gives the MAIN thread a block in the
 * entry stub, and defines these four symbols. Every other thread is started
 * here, so its block is made here: allocated by the creator (a failure is
 * pthread_create's EAGAIN, not a crash in the new thread), filled and
 * installed by the thread itself, as the first thing it does, before any
 * code that could touch a thread-local. Variant II, as ld and glibc lay it
 * out: the image at the start, the thread pointer `memsz` (already rounded up
 * to `align`) above it, and the pointer's first word pointing at itself.
 * The references are WEAK: with no template, or in a gcc link where libc owns
 * fs, all four are 0 and nothing here runs. pxx's own thread block is in gs,
 * so it is not touched. feature-a-pxx-link-has-no-elf-tls */
#if defined(__x86_64__) && defined(SYS_arch_prctl)
extern char __pxx_tls_image[] __attribute__((weak));
extern char __pxx_tls_filesz[] __attribute__((weak));
extern char __pxx_tls_memsz[] __attribute__((weak));
extern char __pxx_tls_align[] __attribute__((weak));
#define PXX_TLS_TCB 64   /* bytes at the thread pointer, as pxx --link's entry stub keeps */

static unsigned long pxx_elftls_align(void) {
  unsigned long al = (unsigned long)__pxx_tls_align;
  return al < 16 ? 16 : al;
}

/* The block a new thread needs, or 0 when the program has no template. */
static void *pxx_elftls_alloc(int *failed) {
  char *img = __pxx_tls_image;
  void *blk;
  *failed = 0;
  if (!img) return 0;
  blk = malloc((unsigned long)__pxx_tls_memsz + PXX_TLS_TCB + pxx_elftls_align());
  if (!blk) *failed = 1;
  return blk;
}

static void pxx_elftls_install(void *blk) {
  unsigned long al = pxx_elftls_align();
  unsigned long msz = (unsigned long)__pxx_tls_memsz;
  char *base, *tp;
  if (!blk) return;
  base = (char *)(((unsigned long)blk + al - 1) & ~(al - 1));
  memset(base, 0, msz + PXX_TLS_TCB);
  memcpy(base, __pxx_tls_image, (unsigned long)__pxx_tls_filesz);
  tp = base + msz;
  *(char **)tp = tp;
  syscall(SYS_arch_prctl, 0x1002 /* ARCH_SET_FS */, tp);
}
#else
static void *pxx_elftls_alloc(int *failed) { *failed = 0; return 0; }
static void pxx_elftls_install(void *blk) { (void)blk; }
#endif

static void *pxx_thr_trampoline(void *p) {
  struct pxx_thr_slot *s = (struct pxx_thr_slot *)p;
  pxx_elftls_install(s->elftls);
  pxx_thr_cur = s;
  if (setjmp(s->exit_jb) == 0)
    s->ret = s->start(s->arg);
  pxx_key_run_dtors();
  /* nothing reads a thread-local after this, and the block is the thread's
     own: the slot outlives it (join reads ret), the block need not */
  free(s->elftls);
  s->elftls = 0;
  return s->ret;
}

/* pthread_exit unwinds to the trampoline, which runs the key destructors and
 * returns the value to the PAL as if start had returned it. On the main thread
 * the process ends once every other crtl thread has ended, as glibc's does. */
void pthread_exit(void *retval) {
  struct pxx_thr_slot *s = pxx_thr_cur;
  int i;
  if (s) {
    s->ret = retval;
    longjmp(s->exit_jb, 1);
  }
  pxx_key_run_dtors();
  for (i = 0; i < PXX_PTHREAD_MAX; i++)
    if (pxx_thr_reg[i].used)
      while (!__pxx_pthread_exited(pxx_thr_reg[i].h)) sched_yield();
  exit(0);
}

/* A detached thread's slot holds its handle, and the kernel writes that handle
 * at thread exit, so the slot cannot be freed at detach time. It is freed here,
 * once the thread has exited: the join then returns at once and releases the
 * stack. Called with the registry lock held, from create (so a program that
 * detaches every thread never runs out of slots) and from detach. */
static void pxx_thr_reap_detached(void) {
  int i;
  for (i = 0; i < PXX_PTHREAD_MAX; i++) {
    if (pxx_thr_reg[i].used && pxx_thr_reg[i].detached && __pxx_pthread_exited(pxx_thr_reg[i].h)) {
      __pxx_pthread_join(pxx_thr_reg[i].h);
      pxx_thr_reg[i].used = 0;
      pxx_thr_reg[i].detached = 0;
      pxx_thr_reg[i].tid = 0;
    }
  }
}

int pthread_create(pthread_t *t, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg) {
  int i, slot = -1, tlsfail;
  long long tid;
  void *elftls = pxx_elftls_alloc(&tlsfail);

  if (tlsfail) return 11;                                               /* EAGAIN */

  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  pxx_thr_reap_detached();
  for (i = 0; i < PXX_PTHREAD_MAX; i++) {
    if (!pxx_thr_reg[i].used) { slot = i; pxx_thr_reg[i].used = 1; break; }
  }
  if (slot < 0) { __pxx_pmutex_unlock(&pxx_thr_reg_lock); free(elftls); return 11; }  /* EAGAIN */

  /* Spawn under the registry lock: PalThreadCreate fills the handle bytes and
     returns the child tid. Serialising spawns is fine for test-scale fan-out. */
  pxx_thr_reg[slot].detached = attr && attr->__detach == PTHREAD_CREATE_DETACHED;
  pxx_thr_reg[slot].start = start;
  pxx_thr_reg[slot].arg   = arg;
  pxx_thr_reg[slot].ret   = 0;
  pxx_thr_reg[slot].elftls = elftls;
  tid = __pxx_pthread_create(pxx_thr_reg[slot].h, pxx_thr_trampoline, &pxx_thr_reg[slot]);
  if (tid <= 0) {
    pxx_thr_reg[slot].used = 0;
    pxx_thr_reg[slot].elftls = 0;
    free(elftls);
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
  if (pxx_thr_reg[slot].detached) return 22;  /* EINVAL: not joinable */

  __pxx_pthread_join(pxx_thr_reg[slot].h); /* blocks on the child-tid futex */
  if (retval) *retval = pxx_thr_reg[slot].ret;

  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  pxx_thr_reg[slot].used = 0;
  pxx_thr_reg[slot].tid  = 0;
  __pxx_pmutex_unlock(&pxx_thr_reg_lock);
  return 0;
}

/* crtl had no pthread_detach, so a C program that detaches its workers did not
 * compile ("call to undeclared function"; found 2026-09-25 by the thread leak
 * census). */
int pthread_detach(pthread_t t) {
  int i, found = 0;
  __pxx_pmutex_lock(&pxx_thr_reg_lock);
  for (i = 0; i < PXX_PTHREAD_MAX; i++) {
    if (pxx_thr_reg[i].used && !pxx_thr_reg[i].detached && pxx_thr_reg[i].tid == (long long)t) {
      pxx_thr_reg[i].detached = 1;
      found = 1;
      break;
    }
  }
  if (found) pxx_thr_reap_detached();   /* it may have exited already */
  __pxx_pmutex_unlock(&pxx_thr_reg_lock);
  return found ? 0 : 3;                  /* ESRCH */
}
