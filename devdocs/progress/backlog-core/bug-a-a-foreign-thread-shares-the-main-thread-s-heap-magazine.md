---
slug: bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine
track: A
prio: 65
type: bug
blocked-by: []
status: backlog
found: 2026-09-01
found-by: frankZ
owner: unassigned
summary: "A thread pxx did not create — a libc pthread, or any thread a linked C library starts — never runs the __pxxclone stub that carves and installs a per-thread TLS block, so it INHERITS its creator's gs and every `gs:` slot it touches is the creator's. Measured: gs_base is BSS_TLS_MAIN on all five threads of test_multithreading. The CRASH this caused is fixed (ba2682d2f made the heap magazine's guard atomic, so a shared magazine is correct); what is left is that the TLS block is not per-thread for foreign threads, which is a design question and touches every slot, not just the magazine."
---

# A foreign thread has no TLS block of its own

Measured 2026-09-01 by frankZ at `c9602d5ce`, binary `76c8be9064e0`.

## The measurement

`test/test_multithreading.pas` creates its four workers with libc
`pthread_create`. At a fault, gdb's `thread apply all printf "%#lx", $gs_base`:

```
Thread 5  gs_base=0x411f98
Thread 4  gs_base=0x411f98
Thread 3  gs_base=0x411f98
Thread 2  gs_base=0x411f98
Thread 1  gs_base=0x411f98
```

`0x411f98` is in BSS and is `BSS_TLS_MAIN` — the main thread's block. One
block, five threads.

The cause is not a bug in the clone stub: `thread_emit.inc`'s `EnsureCloneStub`
carves `TLS_BLOCK_SIZE` bytes off the child's stack, zeroes them, and installs
the base with `arch_prctl(ARCH_SET_GS)`. It is correct and I checked its jump
offset. **A foreign thread simply never executes it**, and `clone` does not
reset gs, so the child starts life pointing at its creator's block.

## What is already fixed, and what is not

`ba2682d2f` made the magazine's ownership guard an `xchg r64, m64`. A shared
magazine is now *correct* — mutual exclusion holds, a loser takes the global
locked path, and blocks may migrate between threads, which a heap allows.
That closed a crash of 20 runs in 20.

**It did not make the block per-thread.** Every other `gs:` slot has the same
exposure, and the magazine is only the one that had a list in it:

- `TLS_SLOT_FIRST_FREE = 13` and the sixteen-slot map above it. Whatever a
  frontend or the RTL parks there, a foreign thread reads and writes the main
  thread's copy.
- The stack-bounds slots the stub's own comment mentions (`a thread whose
  bounds nobody filled fails rsp < 0 and takes the ...` path) — a foreign
  thread inherits the CREATOR's bounds, which are wrong for it rather than
  absent, and a wrong bound is the harder failure.
- Anything added to the block later inherits the hazard by default.

## Why this is not just "call the stub"

The stub runs *inside* `__pxxclone`, between the syscall and the entry point.
There is no equivalent hook for a thread the process did not create. The
shapes worth weighing, none of them free:

1. **Detect and install lazily.** Every `gs:` read first checks a marker — the
   block's self-pointer at slot 0 does not work, since a foreign thread reads
   the creator's valid-looking self-pointer. A gettid comparison needs a
   syscall or a cached value with the same bootstrap problem.
2. **Use real ELF TLS.** `fs` belongs to libc and a pxx program may link one;
   that is exactly why `gs` was chosen. A `__thread`-style model needs the
   loader, which `--emit-obj`/`--shared` do not have (`TlsMainInstalled` is
   already false there).
3. **Accept sharing and make every slot safe**, as `ba2682d2f` did for the
   magazine. Cheapest, and it means the block stops being "thread-local" in
   anything but name — which is the reason to decide it deliberately rather
   than one slot at a time.

This is a fork of intent about the TLS design and it is worth a `decide-` if
whoever picks it up cannot settle it from the code. It matters for
[[the-goal-cross-cross]]'s real programs specifically: DOSBox and anything
linking SDL, GTK or a threaded C library will create threads pxx never sees.

## Not claimed

Filed rather than fixed. The crash is gone; what remains is a design decision
about `gs:` ownership, and taking it while holding the regression umbrella
would be the wrong hands.
