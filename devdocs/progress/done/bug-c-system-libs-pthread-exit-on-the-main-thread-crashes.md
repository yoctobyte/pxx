---
track: C
tags: [system-libs, pthread, glibc, entry]
prio: 30
type: bug
blocked-by: []
summary: "Under --system-libs, glibc's pthread_exit called on the MAIN thread segfaults (in glibc, demangling a pointer at 0x...cdca). glibc unwinds main to the buffer __libc_start_main/__libc_start_call_main sets up; a pxx executable enters at its own _start, so there is none. pthread_exit on other threads works (start_thread has its buffer). crtl's own pthread_exit (no --system-libs) handles main."
status: done
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

## Fix (2026-11-19, pxx2)

The crtl-wrapper route, header-only in `lib/crtl/include/pthread.h` under
`__PXX_SYSTEM_PTHREAD__`. `pthread_exit(v)` becomes
`__pxx_sys_pthread_exit(v)`:

- not the main thread (gettid != getpid): `(pthread_exit)(v)`, libc's own;
- the main thread: wait until /proc/self/stat says num_threads == 1
  (polling every 1 ms), then `exit(0)`, which is what glibc does from its
  unwind buffer: status 0, atexit run. Without /proc it ends only the main
  thread (SYS_exit), so the process still lives until the others finish,
  status 0, but atexit doesn't run.

The main thread's own pthread_key destructors are not run on this path.
Entering through __libc_start_main stays the bigger alternative and isn't
needed for this.

This needed bug-c-system-libs-atexit-is-not-in-libc-so too: a program
that registers atexit failed to load at all under --system-libs.

Tests: c_rumpapi26_sys now builds without -DRUA_MAIN_RETURNS, so the
ticket's own repro is covered. Also new rows c_sysmainpte26 (+ _i386):
two workers, one ending through pthread_exit, atexit, exit status,
gcc-compared.
