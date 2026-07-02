# Threadsafe heap contract by memory-management mode

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-syscall-pthread-shim, feature-parallel-processing
- **Found / Opened:** 2026-06-28, Track A runtime prerequisite for pthread shim

## Motivation

PXX already has meaningful threadsafe refcounting under `--threadsafe`, and the
layout-RTTI helper race ticket established locking around several managed
retain/release paths. That does not automatically prove the heap itself is safe
for real preemptive allocation/free from multiple OS threads.

Before Track B ships a syscall-only pthread shim that can support
multithreaded C libraries, Track A needs an explicit runtime contract for heap
safety, and that contract may differ by memory-management mode.

## Scope

- Audit the active memory-management modes and state which are allowed with
  real preemptive threads:
  - hosted shared heap;
  - static arena / embedded profile;
  - ESP-IDF / FreeRTOS profile;
  - any future conservative or compacting GC profile.
- Define whether each mode is lock-based, per-thread, arena-only, or rejected
  when `--threadsafe` plus real threads are active.
- Verify that allocation, free, realloc, class allocation, managed strings,
  dynamic arrays, and managed-record helpers obey the selected contract.
- Keep refcounting and heap safety separate in the design: atomic/locked
  refcount updates are necessary but not sufficient for concurrent allocation.

## Acceptance

- A short design note or ticket log records the heap contract for each supported
  memory-management mode.
- `--threadsafe` hosted x86-64 allocation/free paths are covered by a
  multi-thread stress test that allocates, resizes, and releases strings,
  dynamic arrays, classes, and raw memory concurrently.
- Unsupported mode/thread combinations fail clearly at compile time or startup.
- `feature-syscall-pthread-shim` can rely on this ticket instead of making its
  own assumptions about heap safety.

## Log

- 2026-06-28 — opened from Track B pthread discussion. User clarified that
  refcounting is partly threadsafe already, but heap safety is less certain and
  may depend on the memory-management mode; that belongs in Track A.

## Part of the multithreading epic (2026-06-30)

Umbrella: [[meta-multithreading]]. Invariant: threading is opt-in/off-by-default;
single-threaded self-build stays byte-identical; no libc (Linux syscalls only).

## Resolution (2026-07-02, v151)

- **Contract recorded** in `devdocs/dev/threading.md` ("Heap contract by
  memory-management mode"): one allocator, four modes — hosted x86-64
  `--threadsafe` (spinlock, the only supported threads+alloc combination),
  hosted x86-64 default (threads rejected at compile time), 32-bit/aarch64
  cross (`--threadsafe` rejected), ESP static arena (single-threaded by
  contract, no clone/futex). Refcount atomics and heap lock kept as separate
  layers both bound to `--threadsafe`.
- **Stress test** `test/test_thread_heap_mixed.pas` (in `make test-threads`):
  4 threads × 1500 iterations concurrently churning AnsiString
  concat/SetLength, dynarray SetLength/element writes, dynarray-of-AnsiString,
  class Create/Free, GetMem/ReallocMem/FreeMem — tag-verified, 0 errors.
- **Clear failures for unsupported combos** (new): `__pxxclone` (under all of
  PalThreadCreate/TThread) is a compile error without
  `--threadsafe`/`{$threadsafe on}`; `--threadsafe` and `{$threadsafe on}`
  are compile errors on non-x86-64 targets (previously silently emitted an
  UNLOCKED "threadsafe" binary). Negative tests in `make test-threads`; all
  thread tests now compile `--threadsafe`.
- feature-syscall-pthread-shim can rely on this: pthread shim must require
  `--threadsafe` (it gets that for free via the `__pxxclone` gate).
