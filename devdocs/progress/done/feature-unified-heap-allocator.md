# Unified syscall-free heap allocator

- **Type:** feature
- **Status:** done
- **Owner:** Claude (Opus 4.8)
- **Unblocks:** feature-static-arena-profile, feature-threadsafe-io-serialization, feature-async-coroutines, feature-parallel-processing
- **Opened:** 2026-06-06 (from todo.md §2d / §4)

## Motivation

`GetMem`/`FreeMem`/`New`/`Dispose`/`ReallocMem` now do real free-list reuse, but
it is first-fit with an 8-byte header, no split/coalesce. Class, string, array,
and raw-memory allocation should share **one** heap path so every target and
managed value goes through the same contract.

## Scope

Design: `../../developer/allocator-platform-design.md`,
`../../developer/garbage-collection-thoughts.md`.

- Unify class/string/array/raw allocation behind one `Alloc`/`Free`/`Realloc`
  contract.
- Add alignment, block splitting, coalescing, in-place resize attempts, and
  size bins — **after** the shared path is correct.
- Keep Linux `mmap`/`munmap` as optional target hooks; bare-metal/ESP32 must not
  depend on them. Memory management is a per-target/per-frontend profile
  (ARC default · arena embedded · hosted conservative+cycle). GC never default,
  never bare metal.

## Acceptance

Alloc/free-heavy programs reuse memory across all value kinds via the shared
path; existing allocator/managed tests stay green; self-host fixedpoint holds.

## Done

Commits `2a3b2f6` + `f6de004`. Class, string, array, and raw-memory allocation
now share **one** pure-Pascal contract — `PXXAlloc`/`PXXFree`/`PXXRealloc` in
`compiler/builtin/builtin.pas` — to which the compiler redirects GetMem/New/class-new,
FreeMem/Dispose, and ReallocMem (`EmitHeapAllocLocked`/`EmitHeapFreeLocked`).
mmap-backed, 8-byte size header + first-fit free list, reused blocks zeroed.
Acceptance met: alloc/free-heavy programs reuse across all value kinds; full
`make bootstrap` (byte-identical fixedpoint) + `make test` + `make test-nilpy`
green.

Deferred (separate tickets, not blocking the dependents above):
- Split/coalesce/in-place-resize/size-bins/alignment → `feature-allocator-quality`.
- Syscall-free target-hook abstraction (mmap optional; bare-metal/ESP32) →
  `feature-static-arena-profile` (the no-syscall profile) and the ESP32 arc.

## Log
- 2026-06-06 — ticket opened from todo.md §2d/§4.
- 2026-06-06 — delivered the shared pure-Pascal allocator contract (2a3b2f6,
  f6de004); reconstructed the lost builtin bodies and fixed the self-host
  regressions (not-typing, constructor-Self, nilpy fixups). Moved to done/.
