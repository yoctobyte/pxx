---
track: A
prio: 20
type: feature
blocked-by: []
summary: "Threads created by __pxxclone leave TLS_SLOT_STACK_LO/_HI zero, so they miss the I/O lock's TLS fast path and still pay a gettid syscall per I/O statement. The stub knows the top of the child's stack and not the bottom; only the allocator does. Two ways to close it, both cheap, neither obviously right."
status: backlog
owner: frankS
---

# Cloned threads still pay gettid per I/O statement

`feature-a-io-lock-owner-from-tls-not-gettid` removed that syscall for the MAIN
thread and left cloned threads exactly as they were. Not a regression and not
unsafe — an unset `TLS_SLOT_STACK_HI` is the fail-safe case, and a miss costs
one `gettid`, which is what they paid before.

## Why the stub cannot just do it

`__pxxclone(flags, childStack, entry, arg, ctidptr)` gets the **top** of the
child's stack and carves the TLS block off it. The **bottom** is known only to
whoever mmap'd the stack. A guessed span is not an option: the check exists to
reject a foreign thread reading an inherited block, and glibc allocates thread
stacks as adjacent mmaps, so a span larger than the real stack can put another
thread's `rsp` inside our range — a false hit in the primitive whose job is
mutual exclusion. Bounds must be exact or absent.

## The two ways

1. **A sixth `__pxxclone` argument, `stackLow`.** Explicit and typed; the stub
   stays the single place that writes the block, which is the property that
   makes "every pxx thread passes through here" true. Costs: three call sites
   (`lib/rtl/palthread.pas`, `lib/rtl/palpthread.pas`, `test/test_thread_clone.pas`)
   and the i386 leg's stack-arg layout. `test_tls_base`'s header argues AGAINST a
   sixth argument — but that was about `CLONE_SETTLS` and four backends of tls
   plumbing, not about arity, so it is not a ruling on this.
2. **`palthread` fills the child's block after `__pxxclone` returns.** No ABI
   change; a thread created through raw `__pxxclone` simply keeps the slow path.
   The write is safe to make late *provided LO goes first and HI last* — the
   child reads zeros until HI lands, and the tid it would then read is its own
   anyway (the bounds only reject FOREIGN readers). Costs: the slot indices
   become a constant the RTL knows, which is the duplicated-ABI smell
   `defs.inc`'s slot map exists to prevent.

Recommendation: **(1)**, because it keeps the slot map a compiler-internal fact.
Worth measuring first whether any real workload does enough I/O off the main
thread to care — the honest answer may be that this stays open.

## Gate

`test_thread_clone`, `test_tls_base`, `test_tthread_sync`, and
`test_threadsafe_io_lock_foreign` (which must still MISS — foreign threads are
not cloned threads and must never take the fast path). A benchmark showing the
syscall actually leaves a threaded workload.
