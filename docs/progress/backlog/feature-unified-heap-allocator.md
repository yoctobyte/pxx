# Unified syscall-free heap allocator

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-static-arena-profile, feature-threadsafe-io-serialization, feature-async-coroutines
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

## Log
- 2026-06-06 — ticket opened from todo.md §2d/§4.
