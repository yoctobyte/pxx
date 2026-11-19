---
track: C
tags: [system-libs, glibc, stdlib, atexit]
prio: 50
type: bug
blocked-by: []
summary: "Under --system-libs a program calling atexit failed at load with `symbol lookup error: undefined symbol: atexit`. glibc keeps atexit in the static libc_nonshared.a, as a one-line wrapper around __cxa_atexit, not in libc.so. <stdlib.h> now maps atexit onto __cxa_atexit(f, 0, 0) when stdlib comes from the system (__PXX_SYSTEM_STDLIB__, cpreproc.inc)."
status: done
owner: pxx2
---

# --system-libs: atexit is not in libc.so

gcc links libc_nonshared.a, whose `atexit(f)` is
`__cxa_atexit((void (*)(void *))f, NULL, __dso_handle)`. pxx imports
straight from libc.so, which has only __cxa_atexit. So an executable that
called atexit wouldn't even start.

Fix: `CHeaderUsesSystemLib('stdlib')` defines `__PXX_SYSTEM_STDLIB__`,
and <stdlib.h> then defines `atexit(f)` as a static inline that calls
`__cxa_atexit(f, 0, 0)`. A pxx executable is the main program, so the DSO
handle is 0. glibc runs these handlers from exit() as usual.

Found with bug-c-system-libs-pthread-exit-on-the-main-thread-crashes.
Test: c_sysmainpte26 (+ _i386).
