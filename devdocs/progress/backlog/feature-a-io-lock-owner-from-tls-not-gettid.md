---
track: A
prio: 40
type: feature
blocked-by: []
summary: "The --threadsafe I/O lock issues a gettid SYSCALL on every I/O statement to identify its owner. Every thread now has a TLS block, so the tid can be cached there and the syscall becomes a load. Pure win on the reentrancy check, which is the common case."
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
