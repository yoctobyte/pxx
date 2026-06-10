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
- 2026-06-10 — scope decision with user (churn defense): target the ISA, not
  the ecosystem. Espressif churns chips ~6-monthly but stopped churning ISAs:
  everything new (C2/C3/C6/H2/P4) is RISC-V RV32IMC-class. So: (1) skip
  Xtensa entirely (classic ESP32/S2/S3 — dead end, Espressif migrating off);
  (2) one RV32IMC backend covers the whole forward roadmap; (3) pin ESP32-C3
  as reference chip — chip-specific surface is just boot image header + ROM
  UART, stable per family; (4) scope fence: NO radio, NO ESP-IDF in v1 —
  that is where the churn lives; acceptance = bare-metal UART hello + GPIO.
  WiFi/BLE later as deliberate version-pinned IDF interop (net_esp32).
  Testing: upstream qemu riscv32 'virt' proves ISA codegen (already in
  tools/run_target.sh); Espressif's qemu fork has ESP32-C3 system emulation
  for the chip-level step.
