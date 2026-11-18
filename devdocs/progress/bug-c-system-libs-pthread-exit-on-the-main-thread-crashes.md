---
track: C
tags: [system-libs, pthread, glibc, entry]
prio: 30
type: bug
blocked-by: []
summary: "Under --system-libs, glibc's pthread_exit called on the MAIN thread segfaults (in glibc, demangling a pointer at 0x...cdca). glibc unwinds main to the buffer __libc_start_main/__libc_start_call_main sets up; a pxx executable enters at its own _start, so there is none. pthread_exit on other threads works (start_thread has its buffer). crtl's own pthread_exit (no --system-libs) handles main."
status: open
owner: pxx2
---

# --system-libs: pthread_exit on the main thread crashes

Repro: test/c_crtl_rumpuser_apis.c built with `--threadsafe --system-libs`
without -DRUA_MAIN_RETURNS: every line printed matches gcc, then SIGSEGV in
libc.so.6 at the final `pthread_exit(0)`.

Ways out: enter main through __libc_start_main when --system-libs links libc
(the bigger change; it also gives libc its normal init), or map pthread_exit
under __PXX_SYSTEM_PTHREAD__ to a crtl wrapper that calls exit(0) when
gettid() == getpid() after waiting for the other threads.
