---
track: A
prio: 45
type: bug
blocked-by: []
summary: "MEASURED: a stack overflow on the MAIN thread runs the SIGSEGV handler and exits 7; the same overflow on a cloned worker exits 139 with the handler never entered. Same binary, one argument apart. sigaltstack(2) is PER-THREAD and is registered only by SetSignalHandler, which the main thread calls -- a cloned thread's alt stack reads sp=0 flags=SS_DISABLE size=0, so SA_ONSTACK has nowhere to put the frame and the kernel kills the process."
status: backlog
owner: frankS
---

# A cloned thread has no sigaltstack, so its stack overflow is unhandleable

Found 2026-08-31 while landing
[[bug-a-the-parked-signal-slots-are-process-wide-and-race-across-threads]].
frankA flagged the SHAPE (`BSS_SIG_ALTSTK` is one process-wide buffer) and
guessed two concurrent faults would collide in it. Measured, the truth is worse
and simpler: **the worker has no alt stack at all.**

## Measured

```
sigaltstack(NULL, &old) from each thread of one --threadsafe program:
  main   sp=4282464  flags=0                size=32768
  worker sp=0        flags=2 (SS_DISABLE)   size=0
```

Consequence, same binary, one argument apart — unbounded recursion until the
guard page:

```
overflow on main:   handler entered, exit 7
overflow on worker: exit 139, NO output, handler never entered
```

## Why

`sigaltstack(2)` is per-thread and is **not inherited across clone**. The only
call site is the `SigInstallAddr` stub (`ir_codegen.inc`), reached from
`SetSignalHandler` — so whichever thread installs the handler is the only thread
that gets an alt stack. The stub's own comment has said so since it was written
(*"a hook installed from a clone(2) thread gets the main thread's registration
only"*); what was missing is that this is not a documentation footnote, it is
the difference between a catchable overflow and `exit 139`.

Note the ordinary faults are FINE on a worker: a nil deref has a working stack,
so the kernel pushes the frame on it and the handler runs. **Only the
out-of-stack case needs the alt stack, which is exactly the case that has no
second chance.**

## The fix, and the part that needs deciding

Each thread needs its OWN alt stack, registered before user code runs — a
shared buffer would be frankA's original bug (two concurrent faults, one
buffer). Two candidates:

1. **The clone stub carves it off the child's stack**, next to the TLS block it
   already carves. The alt stack lives at the TOP of the thread's stack and the
   guard page is at the BOTTOM, so it is still mapped when the stack is
   exhausted — which is the only property it needs. Costs one `sigaltstack`
   syscall per thread in the stub, and shrinks the usable stack by
   `SIG_ALTSTACK_SIZE`. Uniform: every pxx thread passes the stub.
2. **`palthread`'s child entry registers one** from a buffer it allocated.
   Keeps the stub minimal; misses threads created through raw `__pxxclone`, and
   those then keep today's behaviour.

Recommendation: **(1)**, same argument the clone stub already makes for the TLS
block — the failure mode of forgetting is not a crash you can find, it is a
thread that dies silently under the one fault it was supposed to survive.

Foreign threads (glibc `pthread_create`) get glibc's own alt stack or none;
nothing pxx does can reach them. Out of scope, like the inherited-block limit
in the sibling ticket.

## Gate

A test in the shape of the measurement above — overflow on main vs on a worker,
both handled — plus `test_signal_threads`, `test_thread_clone`, and the
stack-size arithmetic in `palthread` if (1) is taken.
