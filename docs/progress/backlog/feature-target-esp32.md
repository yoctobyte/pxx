# Compile target: ESP32 / embedded (RISC-V entry, various MCUs)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-target-arm32
- **Unblocks:** feature-additional-cpu-targets
- **Opened:** 2026-06-06 (user request; roadmap.md Phase 5)

## Motivation

The embedded / bare-metal milestone: ESP32 and similar MCUs, with RISC-V as the
embedded entry point. This is where "various CPU" generalizes and where the
syscall-free runtime profile (static arena, no `mmap`/`brk`) becomes mandatory.

## Scope

Per `../../developer/roadmap.md` Phase 5 and
`../../developer/esp32-esp-idf-roadmap.md`:

- RISC-V code generation (embedded entry point) and/or Xtensa for classic ESP32.
- Bare-metal output format: no Linux ELF/syscalls; linker-defined RAM regions;
  startup without an OS.
- ESP-IDF / FreeRTOS as a target profile; import vendor C SDKs directly (ties to
  the C-header-import arc).
- Depends on the static-arena allocator profile (no host syscalls) —
  `feature-static-arena-profile`.

## Acceptance

A minimal program builds for the embedded target and runs on hardware or an
emulator; the syscall-free runtime profile is exercised; fixedpoint gate adapted
for a cross/bare-metal target.

## Dependency note

`Blocked-by feature-target-arm32` is roadmap staging; the harder real prerequisite
is the static-arena profile and bare-metal runtime, not ARM32 specifically. Move
to `urgent/` if embedded is pulled forward.

## Log
- 2026-06-06 — ticket opened from user request + roadmap Phase 5.
