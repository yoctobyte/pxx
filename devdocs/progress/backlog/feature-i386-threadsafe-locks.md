# i386 --threadsafe runtime locks (heap / ARC / I-O)

- **Type:** feature (backend parity) — Track A
- **Status:** backlog
- **Opened:** 2026-07-03
- **Umbrella:** [[meta-multithreading]]. Split out of
  [[feature-pal-thread-primitives]] while closing its i386 leg.

## Context

The i386 threading MECHANISM is done and verified (2026-07-03): the
`__pxxclone` int-0x80 trampoline (thread_emit.inc — note i386 clone's
tls/ctid registers are swapped vs x86-64), IR_CLONE + 32-bit IR_ATOMIC
codegen in ir_codegen386.inc, and the i386 syscall numbers in palthread.pas
(mmap2/munmap/mprotect/futex/gettid). A 4-thread × 100k futex-mutex counter
test ran exactly (400000) under qemu-i386 with the `--threadsafe` guard
temporarily bypassed.

What remains is why the guard stays: under `--threadsafe` the i386 runtime
would be silently UNLOCKED. The x86-64 pieces to port:

- **Heap spinlock**: EmitAcquireHeapLock/Release (xchg spin on
  BSS_HEAP_LOCK) — EmitAcquireHeapLock386 is an explicit no-op stub today;
  wrap the same alloc/free/ARC call sites the x86-64 backend wraps.
- **ARC decrements**: `lock dec` on the refcount word in the 386 release
  paths (plain dec today).
- **I/O lock**: the reentrant owner-tid lock stubs (EmitIoLockStubs) +
  the IR_IO_LOCK/IR_IO_UNLOCK lowering in ir.inc is gated
  `TargetArch = TARGET_X86_64` at 4 sites — widen to i386 once the 386
  stubs exist.
- Then drop the two guards: compiler.pas:434 (`--threadsafe is x86-64
  only`) — the parser's `__pxxclone requires --threadsafe` gate stays.

## Acceptance

test_palthread / test_mutex / test_atomic_counter / test_tthread compile
with `--threadsafe --target=i386` and run exactly under qemu-i386; heap
stress (concurrent GetMem/FreeMem + managed strings) clean; x86-64
self-host byte-identical.
