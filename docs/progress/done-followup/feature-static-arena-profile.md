# Fixed-static-arena allocator profile

- **Type:** feature
- **Status:** done-followup
- **Owner:** —
- **Blocked-by:** feature-unified-heap-allocator
- **Opened:** 2026-06-06 (from todo.md §2d)

## Motivation

Allocator and managed-value tests currently need `mmap`/`munmap`/`brk`. A
bare-metal / RTOS target has no such syscalls, so there must be a profile that
runs entirely from a fixed static RAM region.

## Scope

- A fixed-static-arena memory profile sharing the unified allocator contract
  (see `feature-unified-heap-allocator`).
- Allocator and managed-value tests pass under this profile with no `mmap`,
  `munmap`, or `brk`.

## Acceptance

The managed-value / allocator regression set passes with the static-arena
profile selected; no host syscalls used for heap.

## Log
- 2026-06-06 — ticket opened from todo.md §2d.
