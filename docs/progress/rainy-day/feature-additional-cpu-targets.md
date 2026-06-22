# Additional CPU targets (rollup: i386 → aarch64 → arm32 → ESP32/RISC-V)

- **Type:** feature
- **Status:** rainy-day 
- **Owner:** —
- **Blocked-by:** feature-target-i386, feature-target-aarch64, feature-target-arm32, feature-target-esp32
- **Opened:** 2026-06-06 (from todo.md §5 / roadmap.md)

## Motivation

x86-64 Linux ELF is the only backend today. The roadmap stages additional CPU
targets, each gated by the byte-identical fixedpoint rule. This is the **rollup**
ticket: it reaches `done/` only when all per-target tickets do.

## Per-target tickets

Tracked individually (chained in roadmap order via their own `Blocked-by`):

1. `feature-target-i386` — i386 Linux (32-bit Intel).
2. `feature-target-aarch64` — ARM64 / AArch64 Linux (Pi 4+).
3. `feature-target-arm32` — ARM32 Linux (Pi 2/3, older).
4. `feature-target-esp32` — embedded / bare metal; RISC-V entry point. See
   `../../developer/esp32-esp-idf-roadmap.md`.

Sub-32-bit targets (AVR, 8051) and the cross-compilation model are noted in
`../../developer/roadmap.md` as later/optional — add tickets when they go active.

## Acceptance

All four per-target tickets in `done/`. Each individually meets its fixedpoint
gate + regression suite before the next is started.

## Log
- 2026-06-06 — ticket opened from todo.md §5 / roadmap.md.
- 2026-06-06 — split into per-target tickets (user request); reframed as a rollup
  blocked by the four.
