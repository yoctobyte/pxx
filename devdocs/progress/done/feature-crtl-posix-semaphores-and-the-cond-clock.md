---
slug: feature-crtl-posix-semaphores-and-the-cond-clock
track: crtl
prio: 40
type: feature
status: done
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [crtl, pthread, semaphore]
blocked-by: []
summary: "DONE 2026-11-22: crtl had no <semaphore.h>; micropython's unix thread layer links sem_init/sem_wait/sem_post. Added unnamed semaphores over crtl's mutex and cond (pshared and named semaphores are ENOSYS). That exposed a real bug: pthread_cond_timedwait read every deadline as CLOCK_MONOTONIC, so a default cond (CLOCK_REALTIME, POSIX's default) waited about 56 years -- sem_timedwait and C11 cnd_timedwait never timed out. The cond now records its clock from pthread_condattr_setclock (added getclock), and the deadline is measured on it. Tests c_sem26 (threaded; x86-64, aarch64) and c_sem1t26 (one thread, no --threadsafe: a plain count, as tcc's tcc.h includes the header without threads)."
---

# POSIX semaphores in crtl, and the clock a cond waits on

## Semaphores

`lib/crtl/include/semaphore.h` and `src/semaphore.c`: sem_init, sem_destroy,
sem_wait, sem_trywait, sem_timedwait, sem_post and sem_getvalue. sem_init with
pshared != 0, and sem_open/close/unlink, set ENOSYS.

The header does NOT include <pthread.h>, and sem_t is 128 bytes of opaque storage
(semaphore.c checks that its struct fits). The first version did include
it, and test-core caught that: c_host_header_needs_cdefs_glue (tcc's tcc.h includes
<semaphore.h>) failed, because <pthread.h> without --threadsafe is refused by
design. semaphore.c now reads a new predefined macro, `__PXX_THREADSAFE__`
(set by --threadsafe in every mode; __PXXRT_THREADSAFE is the --emit-obj
marker only):

- with --threadsafe: the count is kept under a crtl mutex, with a cond to wait on;
- without it: one thread, a plain count. A wait at zero would never return, so
  it fails with EDEADLK. sem_timedwait at zero gives ETIMEDOUT at once.

semaphore.h is in the auto-pull map (no longer in EXCLUDED_HEADERS).
Tests: c_sem26 (threaded), c_sem1t26 (one thread).

## The cond clock

pthread_cond_timedwait converted the absolute deadline using
`__pxx_pmonotonic_ns()` whatever clock the caller had used. That suited QuickJS,
which sets CLOCK_MONOTONIC, but a realtime deadline (about 1.8e18 ns) minus
monotonic uptime is a wait of decades. pthread_cond_t now has an `__clock`
field (0 = CLOCK_REALTIME, so PTHREAD_COND_INITIALIZER stays right). On x86-64
and i386 the padding shrank by one int, so the sizes still match glibc's.
pthread_cond_init copies the field from the attr, and timedwait reads `now` with
clock_gettime on that clock.

QuickJS calls pthread_condattr_setclock(CLOCK_MONOTONIC), so it keeps working.

Test: test/c_semaphore.c, which checks a producer with three consumers,
trywait EAGAIN, timedwait ETIMEDOUT and getvalue, and then timedwait on
realtime, monotonic and default conds. It matches gcc with glibc.
