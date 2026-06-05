# Compile target: ARM64 / AArch64 Linux

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-target-i386
- **Unblocks:** feature-target-arm32, feature-additional-cpu-targets
- **Opened:** 2026-06-06 (user request; roadmap.md Phase 3)

## Motivation

ARM64 (Raspberry Pi 4+) is the first non-x86 ISA — a real test of the
target-abstraction introduced by the i386 work. Reuses that backend
parameterization rather than re-deriving it.

## Scope

Per `../../developer/roadmap.md` Phase 3:

- AArch64 register set, AAPCS64 calling convention, fixed-width instruction
  encoding.
- AArch64 ELF emission and Linux syscall ABI.
- First ISA where instruction encoding differs structurally from x86 (no
  variable-length opcodes) — the encoder must generalize.

## Acceptance

ARM64 output runs on an AArch64 Linux host (e.g. Pi 4); the suite passes; the
build meets the **fixedpoint gate** for the AArch64 target.

## Dependency note

`Blocked-by feature-target-i386` is the roadmap's strategic staging plus reuse of
the target-abstraction it introduces — not a hard ISA requirement. Move to
`urgent/` to pull it forward.

## Log
- 2026-06-06 — ticket opened from user request + roadmap Phase 3.
