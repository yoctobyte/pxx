---
slug: bug-c-the-c-driver-never-allocates-the-heap-lock-word
title: "The C driver never allocated BSS_HEAP_LOCK, so the --threadsafe heap lock was whatever sat at BSS offset 0"
track: C
type: bug
prio: 45
status: done
owner: claude-dupwt
found: 2026-11-20
found-by: claude-dupwt (while routing --system-libs threads, bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there)
---

# The C driver never allocated the heap-lock word

## Before

EmitAcquireHeapLock's TTAS fast path and its contended stub spin on
BSS_HEAP_LOCK. The Pascal driver allocates it in its BSS block, and
EmitProgramPrologue allocates it with the arena. ParseCProgram did neither, so
in a C program the word stayed 0, which means BSS offset 0. Whatever lives
there was the lock.

In a `--threadsafe --system-libs` program with an initialised `__thread`,
offset 0 is the TLS init image. `__thread int tl = 7;` made the lock read as
held, and the first Pascal GetMem (a `#include`d unit, or palhostthread's
pthread_create wrapper) ended in `Runtime error 212: the heap lock was never
released`, with one thread and no signal. This happened on latest-f784b38446
too. With `tl = 0` or no initialiser it ran.

## Now

ParseCProgram allocates the 8-byte word right after BSS_INITIAL_RSP. The
same program prints `alloc ok` in all four modes (plain, --threadsafe,
--system-libs, both).

## Rows

c_tls_threads_libc_ts (test-core): test/c_tls_threads_libc_warns.c built
`--threadsafe --system-libs` prints gcc's output. It died with the 212 before
this fix, because its pthread_create wrapper allocates.

Verified: gate quick GREEN; test-core / test-threads / test-c-conformance as in the TLS ticket.
