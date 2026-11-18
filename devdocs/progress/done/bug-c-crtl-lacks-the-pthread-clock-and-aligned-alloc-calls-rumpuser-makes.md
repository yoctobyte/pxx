---
track: C
tags: [crtl, pthread, malloc, time, rump, netbsd]
prio: 55
type: bug
blocked-by: []
summary: "NetBSD librumpuser (hosted) called what crtl lacked: pthread_key_*/get/setspecific, pthread_exit, pthread_attr_init & co., pthread_spinlock_t, pthread_setname_np, clock_nanosleep, clockid_t, posix_memalign / aligned_alloc / memalign. rumpuser_mem.c, _pth.c, _sp.c, rumpuser.c. Found by frank-user and the kernel session (row 3)."
status: done
owner: pxx2
---

# rumpuser's pthread, clock and aligned-alloc calls

- pthread.c: keys (values in a `__thread` array, destructors at thread end,
  POSIX's 4 rounds); pthread_exit longjmps to the thread's trampoline, and on
  the main thread waits for crtl's threads and exits 0; attr detach state is
  honoured by pthread_create, the stack size kept; spin locks on one int
  (glibc's type); setname/getname_np accepted, no name kept.
- pthread_attr_t re-padded around its new fields: still glibc's 56 / 36 bytes.
- time.h / sys/types.h: clockid_t; time.c: clock_nanosleep (TIMER_ABSTIME as
  time left on that clock; returns the error number).
- stdlib.c: posix_memalign, aligned_alloc, memalign, valloc over-allocate from
  the pool and tag the aligned address ([a-16] the block, [a-8] an odd tag no
  pool size header can equal); free, realloc and malloc_usable_size know it.

Test: test/c_crtl_rumpuser_apis.c (row c_rumpapi26) against gcc + glibc: crtl
x86-64, crtl i386, --system-libs. The --system-libs row returns from main:
bug-c-system-libs-pthread-exit-on-the-main-thread-crashes.
