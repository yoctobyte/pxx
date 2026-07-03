# i386 --threadsafe runtime locks (heap / ARC / I-O)

- **Type:** feature (backend parity) — Track A
- **Status:** done
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

## Resolution (2026-07-03, Track A — same session as the split)

Design: instead of porting x86-64's codegen-site lock wrapping (~35 helper
call sites in the 386 backend + epilogues), the locks live in PASCAL under a
new compile-time define **PXX_TS_SOFTLOCK** (set by the lexer only for
`--threadsafe --target=i386`, so the default build's lexing skips the regions
and every other configuration is byte-identical):

- **Heap**: builtinheap's PXXAlloc/PXXFree take a `__pxxatomic_xchg` spinlock
  (PXXHeapSpin) INSIDE the helpers — every entry path (codegen'd call site or
  another helper's internal allocation) is covered, with no lock recursion
  (helper-internal Pascal→Pascal calls never re-enter the wrapped pair while
  holding it; PXXRealloc's inner Alloc/Free each take it separately).
- **ARC**: PXXStrIncRef/DecRef + PXXDynArrayIncRef/ReleaseDepth refcounts go
  through `__pxxatomic_add` (32-bit rmw on the low word of the 8-byte header;
  counts never carry). Fresh-block init-to-1 stores stay plain (no race).
- **I/O**: EmitIoLockStubs386 (int-0x80 gettid=224 + lock-cmpxchg reentrant
  owner-tid spinlock, the direct port of x86-64's stubs), IR_IO_LOCK/UNLOCK
  cases in the 386 emitter, ir.inc lowering gates widened to i386 (4 sites).
- Guards lifted: compiler.pas `--threadsafe` accepts i386;
  `{$threadsafe on}` accepts i386 only via the flag (the define is applied
  before lexing, a mid-source directive is too late) — clean error says so.
- palthreadobj: Synchronize/Queue/SyncInvokeMethod take `const` TThreadMethod
  (by-ref, i386-compatible); ThreadObjLauncher reordered below Synchronize +
  field-wise method-pointer copy — workarounds for two pre-existing i386
  gaps, one filed as bug-method-call-before-body-byvalue-small-record-arg.

Verified under qemu-i386 (all in `make test-i386`): test_palthread,
test_mutex, test_atomic_counter, test_tthread, test_tthread_sync, and a new
4-thread × 20k GetMem/FreeMem + managed-string churn stress
(test_threadsafe_i386_stress, 5/5 clean). Also green outside the gate:
test_critsec_once, test_tthread_terminate, test_tthread_final, test_condvar
on i386. x86-64 make test + test-threads green; self-host byte-identical.
