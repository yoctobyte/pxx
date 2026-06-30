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
