---
slug: bug-a-the-exception-chain-fix-is-defeated-by-a-libc-pthread
track: A
prio: 70
type: bug
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: [decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part]
summary: "`bug-a-the-exception-shadow-chain-is-process-wide-so-two-threads-crash` moved TLS_SLOT_EXC_TOP into the per-thread TLS block, and its own note says a fresh thread gets a ZEROED block from the clone stub. A libc pthread never runs that stub, so it INHERITS a chain head pointing at its creator's live frames -- and the fix is defeated for exactly the thread kind DOSBox, SDL and every threaded C library create. MEASURED: main thread and one pthread_create'd thread each doing 300k try/except, 3 runs of 3 print `Unhandled exception`; the identical 600k of work on ONE thread in the SAME binary is 3 of 3 clean. At 2k each, one run of three produced no output at all. Repro is test/test_foreign_thread_exception_chain.pas, NOT WIRED because it fails."
---

# A libc pthread inherits its creator's exception chain

Measured 2026-09-02 at `efc33772a`.

## The measurement, with its control

`test/test_foreign_thread_exception_chain.pas` — main thread and one
`pthread_create`d thread, each running `try Boom; except Inc(n) end` in a loop,
counting.

```
foreign thread, 300k each   run1..3: Unhandled exception
same work, ONE thread, 600k run1..3: main=300000 worker=300000 FOREIGNEXC OK
foreign thread, 2k each     run1: OK   run2: (no output at all)   run3: OK
```

The single-threaded row is the control and it is drawn from the same binary and
the same code path — the worker function is called directly instead of through
`pthread_create`. So this is the thread, not the loop.

## Why the existing fix does not cover it

`defs.inc`'s note at `TLS_SLOT_EXC_TOP` states the mechanism exactly:

> A fresh thread gets a ZEROED block from the clone stub, i.e. an empty chain,
> which is exactly right and is the other half of the fix.

**A foreign thread never runs the clone stub.** `clone` does not reset `gs`, so
it starts life pointing at its creator's block with the creator's chain head in
it. Thread A's `try` then links onto thread B's frame and a raise longjmps into
a frame that may already be dead — which is the same sentence that ticket used
to describe the bug it fixed.

This is the concrete, crashing instance of
[[bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine]]. That ticket
is right that the general question is a design decision; this one is not a
design question, it is a program that fails.

## What is already in place, and it is more than the parent ticket says

The parent lists "detect and install lazily" and dismisses the detection half:
*"the block's self-pointer at slot 0 does not work ... a gettid comparison needs
a syscall or a cached value with the same bootstrap problem."*

**That was solved and shipped.** `feature-a-io-lock-owner-from-tls-not-gettid`
established the discriminator inheritance cannot fake — the reader's own `rsp`
against the bounds the block's owner recorded — and it is live in
`ir_codegen.inc:1099-1118`, guarding the I/O lock's cached tid. The parent's
option analysis is stale about its own hardest sub-problem.

So the missing half is not detection. It is **where a foreign thread's block
comes from and what bounds go in it**, which is the decision this is blocked on.
