---
track: C
tags: [crtl, pthread, system-libs, abi, rump, netbsd]
prio: 60
type: bug
blocked-by: []
summary: "crtl's pthread types were far smaller than glibc's (x86-64 mutex 24 vs 40, cond 4 vs 48, attr 4 vs 56; i386 likewise). Under --system-libs crtl's <pthread.h> is still the header but pthread_mutex_lock & co. are glibc's, so glibc wrote past every one; and a struct holding one could not be shared with a gcc-built object. Also under --system-libs pthread_create/join were still renamed to crtl's __pxx_crtl_* and refused (rumpuser bio.c), and crtl had no pthread_rwlock_t at all (rump row 5). Found by frank-user."
status: done
owner: pxx2
---

# crtl pthread types: glibc's layout, and a rwlock

- lib/crtl/include/pthread.h: on x86-64 and i386 every type is padded (crtl's
  fields first) to glibc's size and alignment, measured with gcc. Other
  targets keep crtl's sizes: no glibc headers here to measure against.
- `__PXX_SYSTEM_PTHREAD__` (cpreproc, when pthread is on the system-library
  path, like frank-user's `__PXX_SYSTEM_ASSERT__`) keeps pthread_create/join
  under their own names, so they bind to libc.
- pthread_rwlock_t + rdlock/wrlock/try*/unlock and the attr pair: over the
  PAL futex mutex and condvar words; a waiting writer holds off new readers.

Test: test/c_pthread_layout_rwlock.c (sizes, alignments, 2 writers + 4
readers, the try forms) against gcc + glibc: crtl x86-64, crtl i386, and
--system-libs (glibc's own functions).
