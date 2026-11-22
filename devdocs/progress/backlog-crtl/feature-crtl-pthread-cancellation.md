---
slug: feature-crtl-pthread-cancellation
track: crtl
prio: 35
type: feature
status: backlog
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
