---
track: A
prio: 40
type: feature
blocked-by: []
summary: "DONE 2026-08-31. The --threadsafe I/O lock's owner tid now comes from the thread's TLS block behind a stack-bounds check, not a gettid syscall per I/O statement: 400k Writeln went 0.71s -> 0.49s against 0.48s unlocked, gettid 400000 -> 1. Foreign and cloned threads MISS the fast path and pay gettid, which is the fail-safe direction. Cloned-thread bounds are the one deliberate leftover -> feature-a-tls-stack-bounds-for-cloned-threads."
status: done
owner: frankS
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

## 2026-08-31 — LANDED, with the design above, plus what the ticket's own gate could not see

### What shipped

`TLS_SLOT_TID` / `TLS_SLOT_STACK_LO` / `TLS_SLOT_STACK_HI` in the `defs.inc` slot
map; the entry-point install (`EmitTlsMainInstall`) fills all three for the main
thread; `EmitIoLockStubs` reads the tid only when `stackLow <= rsp < stackHigh`.

Two things the design note above did not settle, decided here:

- **Where the main thread's bounds come from:** `getrlimit(RLIMIT_STACK)` at the
  ELF entry point. That is the kernel's own statement of how far the stack may
  grow, and therefore of how far down it guarantees nothing else is mapped
  (`mmap_base` is placed below that gap). Clamped to 64 MiB for the one case the
  gap does not cover — an rlimit above ~5/6 of the address space is capped below
  itself, and `RLIM_INFINITY` would make `hi - span` wrap. A **failed**
  `getrlimit` needs no branch: the scratch is BSS, so the span reads 0 and the
  test can never pass.
- **HI is written LAST and 0 means "no bounds".** The block starts zeroed, so an
  unset or half-written pair fails `rsp < 0` and takes the slow path. Writing HI
  first would leave LO at 0, which every userspace rsp is above — the same pair,
  in the other order, is a silent false hit.

Numbers, and the shas they came from: `benchmarks/2026-08-31-threadsafe-io-lock-tls.md`.
0.71s -> 0.49s against 0.48s unlocked; `gettid` 400000 -> 1.

### The gate this ticket asked for would have BLESSED the broken build

`Gate:` above says "`test_multithreading` green". Measured, on a compiler with
the stack-bounds check deleted and nothing else changed:

- `test_multithreading` — **PASSES.** It greps for `multithreading test
  completed successfully`, and a lock that lost mutual exclusion still completes.
- `test_threadsafe_io_lock` — **PASSES.** It is single-threaded.

Both of the ticket's own threading gates are blind to the exact defect the
ticket spends three sections explaining. This is frankA's rule of the same day
in another shape: *a read-back test verifies agreement, not correctness* — and
here, a completion marker verifies completion, not exclusion.

So `test/test_threadsafe_io_lock_foreign.pas` asserts **atomicity**: four glibc
`pthread_create` threads write 50 lines of 300 identical characters each (a
`Writeln` is two `write(2)` calls, so an unserialised pair tears), and the
Makefile demands exactly **200 whole lines** plus the `done`. Counting *bad*
lines instead would have scored a crashed run as a pass. Watched failing at
**52, 108 and 57** of 200 on the naive build, with 1200-character torn lines.

### The other test that caught this, and it caught it by being a NEIGHBOUR

`test_tls_base` went `errors=2` — it asserts slots 2..15 are zero in the main
thread's block, and slots 2 and 3 are now the bounds. Its tag moved to slot 4
(`TLS_SLOT_FIRST_FREE`); it has now moved twice, from slot 1 when the tid landed
and from slot 2 when the bounds did. The assertion is worth keeping exactly
because it is about a slot this test does not own.

Its phase 0 and phase B also install their *own* blocks over the entry one,
leaving slots 1..3 zero — so every `Writeln` after that falls back to `gettid`.
That is the fail-safe path being exercised by a test written years before it
existed.

### Left deliberately on the slow path

**Cloned threads.** The clone stub knows the top of the child's stack (the
`childStack` argument) and not the bottom, and only the code that ALLOCATED the
stack does. Their bounds stay zero, so they miss and pay `gettid` — exactly the
behaviour they had before this change, with no new risk. Taking that last slice
means either a sixth `__pxxclone` argument or having `palthread` fill the child's
block after the clone returns; the trade-off is written up in
`feature-a-tls-stack-bounds-for-cloned-threads`.

**Foreign threads miss forever, by design.** That is not a limitation to be
fixed: a thread reading a block it inherited must not be believed.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
