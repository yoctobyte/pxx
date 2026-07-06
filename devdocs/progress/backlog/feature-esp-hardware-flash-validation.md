---
prio: 45  # auto
---

# ESP32 real-hardware flash + boot validation (S2/S3, C3)

- **Type:** feature (validation — requires physical hardware) — Track A
- **Status:** backlog (blocked on hardware access; un-automatable in-harness)
- **Opened:** 2026-06-30 (split from feature-esp32-idf-xtensa, whose QEMU scope is done)

## Scope

The ESP QEMU + GDB path is verified ([[feature-esp32-idf-xtensa]] done). What
remains can only be done with a board on USB:
- Flash a pxx-built ESP32-S2/S3 (Xtensa) + ESP32-C3 (riscv32) image to real silicon.
- Confirm UART boot output matches the QEMU/x86-64 oracle.
- Exercise a live ISR / peripheral (timer/GPIO) on hardware (the QEMU path can't
  install a real vector).

## Acceptance

A pxx ESP image boots on a physical board and its UART output matches the oracle;
a basic peripheral/ISR fires on hardware. Requires the user's board + USB access.
