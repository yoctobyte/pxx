---
prio: 30
track: A
---

# Port the statement-atomic I/O lock to i386/aarch64/arm32

- **Type:** feature — cross threading parity. Track A (codegen: the I/O-lock stub
  emission) + touches the threadsafe runtime.
- **Found:** 2026-07-17, parallel-for cross analysis.

## Gap

`--threadsafe` statement-atomic console I/O (the reentrant owner-tid I/O spinlock,
`IR_IO_LOCK` around `write`/`writeln`/`read`) is **x86-64 only**:
`parser.inc` `EmitIoLockStubs` is gated `TargetArch = TARGET_X86_64`, and
`IR_IO_LOCK` lowering is x86-64-only. On i386/aarch64/arm32 the heap/ARC locks
work (Pascal `PXX_TS_SOFTLOCK`), but concurrent `writeln` from multiple threads
can **interleave mid-line** — output isn't statement-atomic.

Impact is limited: data-parallel `parallel for` bodies (array writes) are
unaffected; only threaded/`parallel` code that writes to the console from workers
sees interleaving. Not a correctness bug for compute; a diagnostics/output
quality gap.

## Direction

Emit the I/O-lock stubs + lower `IR_IO_LOCK` on i386/aarch64/arm32 (the atomics
already exist there — `__pxxatomic_*` land on all four). Mirror the x86-64
BSS_IO_OWNER/BSS_IO_DEPTH reentrant spinlock. Gate = `test_thread_writeln_
interleave.pas` (currently x86-64-only) green on each cross target under qemu.

Part of [[meta-multithreading]] (M5 cross parity). Low priority — cosmetic vs the
compute path.
