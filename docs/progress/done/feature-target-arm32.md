# Compile target: ARM32 Linux

- **Type:** feature
- **Status:** done
- **Owner:** claude
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
- 2026-06-10 — ticket claimed; starting implementation of ARM32 target support.
- 2026-06-11 — completed ARM32 Linux target slice. `make test-arm32` passes
  under `tools/run_target.sh arm32` with output identical to x86-64 for hello,
  arithmetic, procedures, loops, writes, var/out params, raw syscalls, and heap
  allocation/free including pointer dereference, record fields, and static
  array indexing (`test/test_cross_heap.pas`). Added ARM32 stack-argument
  support for helper procedures with more than four parameters and enabled the
  Pascal `builtinheap` allocator path. Commit: e15bd4f.
- 2026-06-11 — added ARM32 managed AnsiString support. The backend now lowers
  literal/char/inline-string conversion, retain/release assignment, by-ref
  store publishing, concat/equality through `PXXStr*` Pascal helpers, string
  writes, pointer-sized string returns, local string cleanup, `IR_SLOTADDR`,
  and inline `tyString` stack-buffer concat. Fixed two ARM32-specific issues
  found during validation: x86-64 managed-local zeroing bytes in ARM32
  procedures, and invalid large ARM immediate encoding for the 272-byte inline
  string buffer. Added `test/test_cross_string.pas` to `make test-arm32`.
