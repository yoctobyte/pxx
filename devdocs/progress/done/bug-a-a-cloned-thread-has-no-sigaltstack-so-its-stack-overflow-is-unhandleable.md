---
track: A
prio: 45
type: bug
blocked-by: []
summary: "MEASURED: a stack overflow on the MAIN thread runs the SIGSEGV handler and exits 7; the same overflow on a cloned worker exits 139 with the handler never entered. Same binary, one argument apart. sigaltstack(2) is PER-THREAD and is registered only by SetSignalHandler, which the main thread calls -- a cloned thread's alt stack reads sp=0 flags=SS_DISABLE size=0, so SA_ONSTACK has nowhere to put the frame and the kernel kills the process."
status: done
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

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1e75fe2d3.

## Fixed (frankA, 2026-09-02) — option (1), x86-64

Taken as recommended: the clone stub carves the alt stack, above the TLS block
rather than below it. **Above matters and the ticket does not say why.** The
child's `rsp` starts sixteen bytes under the TLS block and grows DOWN from
there, so an alt stack carved below would be the region the thread's own calls
run through — it would be overwritten by ordinary work long before a fault
needed it. Carved from the top, it sits at the highest addresses of the mapping
while the guard page is at the lowest, which is the only property it needs.

### Measured, one binary, one argument apart

| | pre-fix `f4107b6da95e` | post-fix `6bcfc4f4c068` |
| --- | --- | --- |
| overflow on main | `handled code=1 ... handler-in-bss=TRUE`, exit 7 | identical |
| overflow on a worker | **no output at all, exit 139** | `handled code=1 ... handler-in-bss=FALSE`, exit 7 |

### The assertion is not "did we survive"

`test/test_thread_sigaltstack.pas` asserts `handler-in-bss`, which must answer
**differently on the two threads**: main's alt stack is the process-wide BSS
buffer `SetSignalHandler` registers (TRUE), the worker's is carved off its own
mmap'd stack (FALSE). A fix that handed every thread the BSS buffer would pass
a survival test and print TRUE twice — and it would be the bug this ticket's
own text warns about, two concurrent faults pushing frames onto one region.
The main row is also the control: byte-identical across the fix.

### Also landed

`lib/rtl/palthread.pas` grew `PAL_MIN_STACK = 128 * 1024`. The stub now carves
1152 + 32768 bytes before the child's first instruction, so a smaller request
would have it writing past the mapping — and into another thread's storage
rather than onto this one's guard page, so it would not even look like a stack
problem. **Necessity not demonstrated by a caller:** every call site in the tree
passes 0 (the default), so nothing exercises it today; it is there because the
stub's requirement is new and invisible from the call site.

### Not done, and named rather than left

The other three legs of `EnsureCloneStub` — i386, aarch64, arm32 — have the same
gap. Filed as
[[bug-a-the-clone-stub-registers-a-signal-alt-stack-on-x86-64-only]] rather than
written blind: the property is "the kernel delivered onto the alt stack", the
only way to run those targets here is qemu-user, and
[[bug-a-riscv32-sa-onstack-has-no-effect-under-qemu]] already records that
`SA_ONSTACK` does not take effect there. A cross run could not have told a wrong
stub from qemu ignoring the flag.

Gate: `make compiler/pascal26` converged, `tools/gate.sh quick` GREEN with the
FPC seed canary live, and `test_signal_threads`, `test_thread_clone`,
`test_palthread`, `test_multithreading` all green by hand.
