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
