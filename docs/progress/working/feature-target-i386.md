# Compile target: i386 (32-bit x86 Linux)

- **Type:** feature
- **Status:** working
- **Owner:** claude
- **Blocked-by:** chore-qemu-test-env
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

This is the first new target and the one that introduces the target-abstraction
the chain depends on. Reprioritize by moving to `urgent/`. Blocked on the QEMU
test environment (chore-qemu-test-env): every target must run its regression
suite and fixedpoint gate on the dev host via `tools/run_target.sh`.

## Log
- 2026-06-06 — ticket opened from user request + roadmap Phase 2.
- 2026-06-10 — blocked-by chore-qemu-test-env added: test environment precedes the backend.
- 2026-06-10 — user rationale: i386 matters only as 32-bit proving ground for ESP32; CPU itself is not a goal.
- 2026-06-10 — first vertical slice landed: `--target=i386` flag, TargetArch
  global, target-dispatched EmitExit/EmitwriteSyscall/EmitDataRef (int 0x80
  ABI; 4-byte data fixups), i386 entry stub, minimal IR walker
  (ir_codegen386.inc: const-str write/writeln/labels/jumps), ELF32 writer
  (writeELF32: ET_EXEC/EM_386, one PT_LOAD at 0x08048000, whole-file map at
  p_offset 0). hello.pas runs under qemu-i386 and natively (`make test-i386`).
  Unsupported constructs are hard errors, never mis-compiles: proc prologue,
  heap/string/exception runtimes, externals, and unknown IR ops all refuse
  with named errors. x86-64 fixedpoint + make test + test-nilpy green.
  Next increments: int locals/arith (IR const_int/store/load, i386 reg set),
  proc prologue/calls (32-bit frame), then runtime emitters.
