# Compile target: ARM32 Linux

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-target-aarch64
- **Unblocks:** feature-target-esp32, feature-additional-cpu-targets
- **Opened:** 2026-06-06 (user request; roadmap.md Phase 4)

## Motivation

ARM32 (Raspberry Pi 2/3, older Pi) extends the ARM work to the 32-bit ABI and
brings the toolchain a step closer to the embedded/bare-metal entry point.

## Scope

Per `../../developer/roadmap.md` Phase 4:

- ARM32 (ARMv7-A) register set, EABI calling convention, 32-bit pointers.
- Thumb vs ARM instruction-set decision.
- ARM32 ELF emission and Linux syscall ABI.

## Acceptance

ARM32 output runs on an ARMv7 Linux host (e.g. Pi 2/3); the suite passes; the
build meets the **fixedpoint gate** for the ARM32 target.

## Dependency note

`Blocked-by feature-target-aarch64` reflects shared ARM backend infrastructure +
roadmap staging, not a hard requirement. Move to `urgent/` to pull it forward.

## Log
- 2026-06-06 — ticket opened from user request + roadmap Phase 4.
