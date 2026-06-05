# Additional CPU targets (i386 → aarch64 → arm32 → RISC-V)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §5 / roadmap.md)

## Motivation

x86-64 Linux ELF is the only backend today. The roadmap stages additional CPU
targets, each gated by the byte-identical fixedpoint rule.

## Scope (staged, per `../../developer/roadmap.md`)

1. i386 Linux (32-bit Intel).
2. ARM64 / AArch64 Linux (Raspberry Pi 4+).
3. ARM32 Linux (Pi 2/3, older).
4. Embedded / bare metal (ESP32 and similar); RISC-V as the embedded entry
   point. See `../../developer/esp32-esp-idf-roadmap.md`.

Sub-32-bit targets (AVR, 8051) and the cross-compilation model are noted in
roadmap.md as later/optional.

## Acceptance

Each target builds and passes its fixedpoint gate + regression suite before the
next is started. Split into per-target tickets when one becomes active.

## Log
- 2026-06-06 — ticket opened from todo.md §5 / roadmap.md.
