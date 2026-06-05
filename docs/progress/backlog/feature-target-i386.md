# Compile target: i386 (32-bit x86 Linux)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-target-aarch64, feature-additional-cpu-targets
- **Opened:** 2026-06-06 (user request; roadmap.md Phase 2)

## Motivation

x86-64 Linux ELF is the only backend today. i386 is the first additional target
(roadmap Phase 2) — closest to the existing x86-64 path, so it is the place where
the backend first becomes **target-parameterized**. That abstraction is what the
later ARM/embedded targets reuse, which is why this one comes first.

## Scope

Per `../../developer/roadmap.md` Phase 2:

- 32-bit register set, calling convention, and pointer width.
- i386 ELF emission (header, relocations, syscalls).
- Parameterize the IR→machine emitter so target selection is explicit, not
  hardcoded x86-64.

## Acceptance

i386 output runs on a 32-bit (or multilib) host; the suite passes; the build
meets the byte-identical **fixedpoint gate** for the i386 target.

## Note

`Blocked-by` is empty: this is the first new target and the one that introduces
the target-abstraction the chain depends on. Reprioritize by moving to `urgent/`.

## Log
- 2026-06-06 — ticket opened from user request + roadmap Phase 2.
