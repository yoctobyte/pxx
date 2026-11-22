---
slug: feature-crtl-pthread-cancellation
track: crtl
prio: 35
type: feature
status: done
closed: 2026-11-22
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [crtl, pthread]
blocked-by: []
summary: "crtl has no pthread_cancel, pthread_setcanceltype, pthread_setcancelstate, pthread_testcancel or the PTHREAD_CANCEL_* constants. micropython's unix thread layer calls pthread_cancel on still-running threads at exit (mp_thread_deinit) and sets PTHREAD_CANCEL_ASYNCHRONOUS in every new thread. The scratch build defined them away with -D."
---

# pthread cancellation in crtl

## Who needs it

micropython v1.24.1, ports/unix/mpthreadport.c:

- `mp_thread_start`: `pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, NULL);`
- `mp_thread_deinit`: `pthread_cancel(th->id)` for every thread still running
  when the interpreter exits.

To get it linked, the scratch build used:

```
'-Dpthread_cancel(t)=((void)(t),0)' '-Dpthread_setcanceltype(a,b)=0' -DPTHREAD_CANCEL_ASYNCHRONOUS=1
```

## Shape

Deferred cancellation, which is the default, is the part worth having:

- a per-thread pending flag, set by pthread_cancel;
- tested at the cancellation points crtl owns (pthread_cond_wait and
  timedwait, pthread_join, sleep/nanosleep, sem_wait, read, write) and in
  pthread_testcancel;
- acted on as pthread_exit(PTHREAD_CANCELED). pthread_exit already unwinds
  with a longjmp to the thread trampoline, see pthread.c exit_jb.

Asynchronous cancellation means a signal, and a thread that stops wherever it
happens to be. glibc does that with SIGCANCEL. It is rarely safe in practice.
A first version could accept the type and behave as deferred, and the ticket
should say so. For micropython at exit, any of these works: its threads are
not inside a cancellation-sensitive section then.

Constants (glibc): PTHREAD_CANCEL_ENABLE 0, DISABLE 1, DEFERRED 0,
ASYNCHRONOUS 1, PTHREAD_CANCELED ((void *)-1).

## Done (2026-11-22)

- pthread.h: PTHREAD_CANCEL_ENABLE/DISABLE/DEFERRED/ASYNCHRONOUS and
  PTHREAD_CANCELED with glibc's values; pthread_cancel,
  pthread_setcancelstate, pthread_setcanceltype and pthread_testcancel.
- The pending flag, state and type live in the thread's registry slot, so
  pthread_cancel on another thread can see the type. Acting on a cancel is
  pthread_exit(PTHREAD_CANCELED): key destructors run, and join returns
  PTHREAD_CANCELED.
- **Deferred:** acted on at pthread_testcancel, at pthread_join's entry,
  around pthread_cond_wait/timedwait (with the mutex held, as glibc does),
  and at sem_wait/timedwait's entry. The semaphore waits run with
  cancellation disabled, so a cancel never leaves the semaphore's lock
  held.
- **Asynchronous:** signal 32 (glibc's SIGCANCEL), installed with
  SA_RESTART on the thread's own stack (crtl's sigaction honours both since
  bug-crtl-sigaction-ignores-sa-flags-...). Its handler exits the thread
  from wherever it is. Setting ENABLE or ASYNCHRONOUS with a cancel pending
  acts at once.

Not covered, and stated in pthread.h:
- A thread BLOCKED in a deferred cancellation point is not woken by the
  cancel. It is checked when the wait returns. glibc interrupts the wait.
- Threads crtl did not start, the main thread among them, cannot be
  cancelled (ESRCH). setcancelstate and setcanceltype work on them.
- sleep, nanosleep, read and write are not cancellation points.
- There is no pthread_cleanup_push/pop yet.

Test c_pthread_cancel, against gcc+glibc: deferred with a key destructor,
disabled then enabled, asynchronous in a busy loop, a sem_wait loop, the
state on main, and EINVAL for bad values. 10 of 10 runs on x86-64, 3 of 3
on aarch64 and on i386.

micropython built by pxx without the three -D workarounds (the real
pthread_cancel and setcanceltype): 898 of 908, the same 10 failures gcc's
build also has. The only -D left in that build is
MICROPY_PY_MATH_SPECIAL_FUNCTIONS=0 (decide-crtl-special-math, owner).
