---
track: A
prio: 40
type: feature
blocked-by: []
summary: "The --threadsafe I/O lock issues a gettid SYSCALL on every I/O statement (measured: 43% overhead, one syscall per Writeln; caching it in TLS removed the whole penalty). The naive version is WRONG -- foreign threads (glibc pthread_create) inherit the creator's block and would answer 'lock already mine', silently losing mutual exclusion. Needs the stack-bounds validation design recorded in the ticket."
status: backlog
owner: ""
---

# The I/O lock does a syscall per I/O statement

- **Track A** (`compiler/ir_codegen.inc` `EmitIoLockStubs`, plus the three
  per-arch ports).
- Recorded in [[feature-a-tls-block-for-the-main-thread]] while landing the
  main-thread TLS block; that ticket is what makes this possible.

## The cost

`EmitIoLockStubs` opens with

```
mov rax, 186    ; gettid
syscall
mov rsi, rax
cmp [BSS_IO_OWNER], rsi
je  ...         ; already ours -> depth bump
```

That is a syscall **per `Writeln`, per `Write`, per `Read`** in a `--threadsafe`
build — including the reentrant case, which is the common one (a write argument
calling a function that itself writes). The stub's own comment says why: *"gettid
is one syscall per I/O statement (no TLS yet)"*. There is TLS now.

## The change

Cache the tid in a TLS slot and read it instead:

```
mov rsi, fs:[0]        ; the block
mov rsi, [rsi + TLS_TID]
```

Two loads, no kernel entry. The slot is filled where the block is installed —
the clone stub already has the tid available (the parent's `clone` return is the
child's tid, but the CHILD needs it, so it is a `gettid` **once per thread**
rather than once per statement), and the main thread's install does the same.

Reserve a named slot index for it rather than an ad-hoc offset; `TLS_BLOCK_SIZE`
is 16 slots and only slot 0 is spoken for.

## Measure, do not assume

Benchmark before claiming a win: a `gettid` is a cheap syscall and an I/O
statement already does a `write`, so the *ratio* is what matters and it will be
much better for buffered output than unbuffered. `bench/` has the
`threadsafe_heap_scaling` shape to copy — hold total work constant, vary threads.
Do not repeat the mistake this repo has on record of writing a plausible speedup
into a ticket without diffing against a measurement.

## Gate

`test_threadsafe_io_lock`, `test_multithreading`, `test_tthread_sync` green and
repeated; the reentrant path (a write argument that itself writes) explicitly
exercised; self-host byte-identical; a benchmark number in `benchmarks/`.

## 2026-08-21 — TRIED, MEASURED, REVERTED. The premise is wrong and here is the fix that would work

### The measurement was right and is worth keeping

400k `Writeln`s: **0.58s unlocked, 0.82s `--threadsafe`** — 43% overhead — and
`strace -c` put **exactly one `gettid` per `Writeln`**, a third of all syscalls.
With the tid cached in a TLS slot: **0.57s**, i.e. the entire `--threadsafe` I/O
penalty gone on that workload, and `gettid` down from 10000 to 1.

So the prize is real. It is also unavailable, for a reason that has nothing to do
with the measurement.

### Why it cannot be taken

**A pxx program can host threads it did not create.** `test_multithreading` —
which has been in the suite for months — spawns its threads with **glibc
`pthread_create`**. Those threads never pass through the clone stub, and the
thread-pointer base is **inherited across clone**, so such a thread reads the
*creating* thread's block.

For `__pxxTlsBase` as a primitive that is a documented alias. For the I/O lock it
is fatal: the foreign thread reads the main thread's cached tid, `cmp
[BSS_IO_OWNER], rsi` answers **"already mine"** for a lock it does not hold, the
acquire is skipped, and mutual exclusion is silently lost — in the primitive
whose entire job is mutual exclusion. Then `IOUnlock` decrements a depth the
thread never incremented.

**No content check fixes this.** Inheritance reproduces the block byte for byte,
so a magic word, a self-pointer check, a version stamp — all pass.

(The attempt also surfaced a worse bug in the neighbouring commit, which is the
real value of having tried: the block was being installed in **`fs`**, where
glibc keeps *its* thread pointer, so every glibc-linked pxx program segfaulted.
Moved to `gs`; `test_glibc_tls_coexist` now guards it.)

### The design that does work

Ground truth that inheritance cannot fake is the **stack**. Threads do not share
one.

- Store `stackLow` / `stackHigh` in the block alongside the tid, written by
  whoever installs it (the clone stub knows the child's stack exactly; the
  entry-point install can take `rsp` at entry as the high bound).
- Fast path: read the base, check `stackLow <= rsp < stackHigh`, use the cached
  tid. Two compares.
- Miss — a foreign thread, or a handler running on the sigaltstack — falls back
  to `gettid`. Correct, just not faster, which is the right way round.

Note the sigaltstack interaction is a **feature** here: a signal handler that
writes runs with `rsp` outside the thread's stack, fails the check, and takes the
slow path rather than trusting a slot.

### Also worth doing, and cheaper

The benchmark shows **two `write` syscalls per `Writeln`** (payload + newline).
Buffering console output would beat this entire ticket on the same workload and
helps the unlocked build too. Probably a separate ticket; noted here because a
measurement that turns up a bigger constant next door should not be thrown away.

### Status

Back to `backlog` with the design above and the numbers to beat. Not blocked —
just not a small change any more, and the small version is actively wrong.
