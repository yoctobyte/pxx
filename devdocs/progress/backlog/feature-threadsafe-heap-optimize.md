---
prio: 53  # auto
---

# Threadsafe heap — optimize + cross-target (M5)

- **Type:** feature (codegen / runtime — optimization) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Umbrella:** [[meta-multithreading]]. Follows the M0 contract
  [[feature-threadsafe-heap-contract]] (correctness) — this is the *speed* half.
- **Relation:** correctness-over-speed (user rule) — do AFTER the contract holds.

## Invariant

Threading is **opt-in**, off by default; the single-threaded self-build stays
**byte-identical**. **No libc** — built on [[feature-pal-thread-primitives]]
(syscalls only). Milestones land in any order under [[meta-multithreading]].

## Scope

Today `--threadsafe` = a coarse global `lock`-prefix on every alloc/free +
refcount, **x86-64 only**. Make it fast + portable:
- **Per-thread heap arenas** (or a lock-free free-list fast path) so uncontended
  alloc/free doesn't serialise on one global lock.
- **Cross-target the threadsafe atomics** — i386/arm32/aarch64/riscv32 currently
  reject `--threadsafe` (only x86-64 has the lock prefix). Add LL/SC / `ldrex`/
  `amoadd` equivalents.
- Benchmark alloc throughput single- vs multi-thread; guard against regression.

## Acceptance
- Multi-thread alloc benchmark scales (no single-lock cliff); `--threadsafe`
  accepted + correct on the cross targets; single-thread alloc unchanged; self-host
  byte-identical.

## Update — thread-safe heap VALIDATED under contention (2026-06-30)
test_thread_heap (lib/rtl + TThread): 4 threads x 12000 GetMem/FreeMem of 128B,
each fills its block with a thread-unique tag and reads it back. WITH --threadsafe:
0 errors across runs (the existing x86-64 lock-prefixed spinlock around PXXAlloc/
PXXFree holds). WITHOUT --threadsafe: SIGSEGV every run — proving threaded
allocation genuinely requires the flag (the M5 contract). In make test-threads
(compiled --threadsafe). The *optimisation* part of M5 (per-thread arenas /
lock-free fast path) is still open; correctness is now demonstrated + gated.
