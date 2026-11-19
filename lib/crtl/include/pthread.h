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

/* GLIBC'S SIZES AND ALIGNMENT, on the targets where pxx code can meet glibc.
 * Under --system-libs these declarations are still the header, but
 * pthread_mutex_lock & co. bind to glibc, which writes its own layout: crtl's
 * 24-byte mutex against glibc's 40, a 4-byte cond against 48 and attr against
 * 56 meant glibc wrote past every one (found by frank-user, rumpuser bio.c).
 * And a struct holding one, shared with a gcc-built object, must lay out the
 * same. crtl's own fields come first; the padding only fills to glibc's size.
 * Measured with gcc against glibc on x86-64 and i386; the other targets keep
 * crtl's own sizes (no glibc to check against here).
 * bug-c-crtl-pthread-types-are-smaller-than-glibc-s */
#if defined(__x86_64__)
#define __PXX_PT_MUTEX_PAD   long __pxx_pad[2];
#define __PXX_PT_COND_PAD    int __pxx_pad[9]; long long __pxx_align;
#define __PXX_PT_ATTR_PAD    long __pxx_pad[5];
#define __PXX_PT_RWLOCK_PAD  int __pxx_pad[7]; long long __pxx_align;
#elif defined(__i386__)
#define __PXX_PT_MUTEX_PAD   long __pxx_pad[2];
#define __PXX_PT_COND_PAD    int __pxx_pad[11];
#define __PXX_PT_ATTR_PAD    int __pxx_pad[6];
#define __PXX_PT_RWLOCK_PAD  int __pxx_pad[3];
#else
#define __PXX_PT_MUTEX_PAD
#define __PXX_PT_COND_PAD
#define __PXX_PT_ATTR_PAD
#define __PXX_PT_RWLOCK_PAD
#endif

/* Thread identity = the kernel tid; copyable by value, compared with ==. */
typedef long pthread_t;

/* pthread_mutex_t starts with the futex word, laid out to match palsync's
 * TMutex (record State: Integer), which is all the Pascal side ever touches.
 * The type, owner tid and depth after it are C-side only and make a RECURSIVE
 * mutex re-lockable by its owner. Zeroed == a free NORMAL mutex, so a {0}
 * static initialiser and MallocZero both yield a valid unlocked mutex. */
typedef struct { int __state; int __type; long __owner; int __count; __PXX_PT_MUTEX_PAD } pthread_mutex_t;
#define PTHREAD_MUTEX_INITIALIZER { 0 }

/* The type is honoured for RECURSIVE; ERRORCHECK locks like NORMAL. It used
 * to be accepted and ignored, so stock threadsafe SQLite (which re-locks a
 * recursive mutex) deadlocked on its first statement. */
typedef struct { int __type; } pthread_mutexattr_t;
/* crtl's fields first, then the pad to glibc's size (56 / 36). */
typedef struct { int __detach; int __flags; unsigned long __stacksize; __PXX_PT_ATTR_PAD } pthread_attr_t;
#define PTHREAD_CREATE_JOINABLE  0
#define PTHREAD_CREATE_DETACHED  1
#define PTHREAD_PROCESS_PRIVATE  0
#define PTHREAD_PROCESS_SHARED   1
#define PTHREAD_STACK_MIN        16384
int pthread_attr_init(pthread_attr_t *a);
int pthread_attr_destroy(pthread_attr_t *a);
int pthread_attr_setdetachstate(pthread_attr_t *a, int state);
int pthread_attr_getdetachstate(const pthread_attr_t *a, int *state);
int pthread_attr_setstacksize(pthread_attr_t *a, unsigned long size);
int pthread_attr_getstacksize(const pthread_attr_t *a, unsigned long *size);

/* glibc's: a plain int word */
typedef volatile int pthread_spinlock_t;
int pthread_spin_init(pthread_spinlock_t *l, int pshared);
int pthread_spin_destroy(pthread_spinlock_t *l);
int pthread_spin_lock(pthread_spinlock_t *l);
int pthread_spin_trylock(pthread_spinlock_t *l);
int pthread_spin_unlock(pthread_spinlock_t *l);

typedef unsigned int pthread_key_t;
#define PTHREAD_KEYS_MAX               128
#define PTHREAD_DESTRUCTOR_ITERATIONS  4
int   pthread_key_create(pthread_key_t *k, void (*destructor)(void *));
int   pthread_key_delete(pthread_key_t k);
void *pthread_getspecific(pthread_key_t k);
int   pthread_setspecific(pthread_key_t k, const void *v);
#define PTHREAD_MUTEX_NORMAL     0
#define PTHREAD_MUTEX_RECURSIVE  1
#define PTHREAD_MUTEX_ERRORCHECK 2
#define PTHREAD_MUTEX_DEFAULT    PTHREAD_MUTEX_NORMAL

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
/* Handlers around fork(): prepare in reverse registration order, parent and
   child in registration order (POSIX). */
int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void));

/* Condition variable — palsync's seq-futex condvar (first word = the futex
 * generation counter). Zeroed == valid, so {0} static init works. The clock
 * attribute is accepted and ignored: timedwait measures a RELATIVE budget on
 * the monotonic clock, which is what CLOCK_MONOTONIC callers (QuickJS) want;
 * CLOCK_REALTIME absolute deadlines are approximated the same way. */
typedef struct { int __seq; __PXX_PT_COND_PAD } pthread_cond_t;
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

/* Reader-writer lock, over the same futex mutex and condvar words: any number
 * of readers or one writer; a waiting writer holds off new readers so a
 * stream of readers cannot starve it. Zeroed == unlocked. rumpuser's
 * locks (librumpuser) are built on it. glibc's size under --system-libs. */
typedef struct {
  int __lock;     /* futex mutex word guarding the fields below */
  int __seq;      /* condvar word: state changed */
  int __readers;  /* readers holding it */
  int __writer;   /* 1 while a writer holds it */
  int __wwait;    /* writers waiting */
  __PXX_PT_RWLOCK_PAD
} pthread_rwlock_t;
#if defined(__x86_64__)
typedef struct { long __kind; } pthread_rwlockattr_t;               /* glibc: 8, aligned 8 */
#else
typedef struct { int __kind; int __pxx_pad; } pthread_rwlockattr_t; /* 8, aligned 4 */
#endif
#define PTHREAD_RWLOCK_INITIALIZER { 0 }

int pthread_rwlock_init(pthread_rwlock_t *rw, const pthread_rwlockattr_t *attr);
int pthread_rwlock_destroy(pthread_rwlock_t *rw);
int pthread_rwlock_rdlock(pthread_rwlock_t *rw);
int pthread_rwlock_tryrdlock(pthread_rwlock_t *rw);
int pthread_rwlock_wrlock(pthread_rwlock_t *rw);
int pthread_rwlock_trywrlock(pthread_rwlock_t *rw);
int pthread_rwlock_unlock(pthread_rwlock_t *rw);
int pthread_rwlockattr_init(pthread_rwlockattr_t *a);
int pthread_rwlockattr_destroy(pthread_rwlockattr_t *a);

pthread_t pthread_self(void);
int  pthread_equal(pthread_t a, pthread_t b);

/* THE LINK NAMES ARE crtl's OWN, not the POSIX ones. The thread runtime under
 * these (lib/rtl/palthread.pas) imports libc's pthread_create/pthread_join
 * BY THOSE NAMES, weakly, to start a thread glibc knows about. An --emit-obj
 * object carries both that import and these bodies, and if the bodies were
 * exported as `pthread_create` every linker would bind the import to them:
 * pthread_create called itself through the PAL and deadlocked on its own
 * registry lock (Nilix s13). Renamed, every pxx C caller -- `&pthread_create`
 * included -- reaches crtl's copy, all objects still share ONE weak copy of
 * the family and its registry, and the import reaches libc or nothing.
 * bug-a-an-object-s-crtl-definition-captured-the-runtime-s-own-libc-import */
#ifndef __PXX_SYSTEM_PTHREAD__   /* --system-libs: libc's own, by their names */
#define pthread_create __pxx_crtl_pthread_create
#define pthread_join   __pxx_crtl_pthread_join
#endif
int  pthread_create(pthread_t *t, const pthread_attr_t *attr,
                    void *(*start)(void *), void *arg);
int  pthread_join(pthread_t t, void **retval);
int  pthread_detach(pthread_t t);
void pthread_exit(void *retval) __attribute__((__noreturn__));
int  pthread_setname_np(pthread_t t, const char *name);
int  pthread_getname_np(pthread_t t, char *name, unsigned long len);

#ifdef __PXX_SYSTEM_PTHREAD__
/* --system-libs: pthread_exit ON THE MAIN THREAD. glibc unwinds the main
 * thread to a buffer __libc_start_main set up; a pxx executable enters at its
 * own _start, so there is none and glibc segfaults demangling it. On every
 * other thread libc's pthread_exit is right (start_thread has its buffer).
 * On main this does what glibc does from there: the process lives on until
 * the last thread is gone, then exits with status 0, running atexit. "The
 * last thread" is read from /proc/self/stat (num_threads); without /proc the
 * main thread just ends (SYS_exit), and the process still lives until the
 * others finish, with status 0 but no atexit. Not run here: the main
 * thread's own pthread_key destructors.
 * bug-c-system-libs-pthread-exit-on-the-main-thread-crashes */
#include <sys/syscall.h>
long syscall(long number, ...);
void exit(int status);

static int __pxx_sys_nthreads(void) {
  char b[512];
  long fd, n, i;
  int field = 2, num = 0;
  fd = syscall(SYS_openat, -100L /* AT_FDCWD */, "/proc/self/stat", 0L);
  if (fd < 0) return -1;
  n = syscall(SYS_read, fd, b, (long)sizeof b - 1);
  syscall(SYS_close, fd);
  if (n <= 0) return -1;
  /* comm, field 2, is in parentheses and may hold spaces: count from the
     LAST ')'. num_threads is field 20. */
  for (i = n - 1; i > 0 && b[i] != ')'; i--) ;
  for (i++; i < n; i++) {
    if (b[i] != ' ') continue;
    if (++field == 20) {
      for (i++; i < n && b[i] >= '0' && b[i] <= '9'; i++) num = num * 10 + (b[i] - '0');
      return num;
    }
  }
  return -1;
}

static void __pxx_sys_pthread_exit(void *retval) {
  long pause[2];
  int n;
  if (syscall(SYS_gettid) != syscall(SYS_getpid))
    (pthread_exit)(retval);           /* not main: libc's own */
  pause[0] = 0;
  pause[1] = 1000000;                 /* 1 ms */
  for (;;) {
    n = __pxx_sys_nthreads();
    if (n == 1) exit(0);
    if (n < 0) for (;;) syscall(SYS_exit, 0L);
    syscall(SYS_nanosleep, pause, 0L);
  }
}
#define pthread_exit(retval) __pxx_sys_pthread_exit(retval)
#endif

#endif /* _PXX_PTHREAD_H */
