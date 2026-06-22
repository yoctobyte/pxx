# Demo — Conway's Game of Life

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-19
- **Closed:** 2026-06-21
- **Relation:** demo-class candidate from idea-demo-app-candidates (top-10).
  Smallest of the set; exercises **bit packing** (cell rows) — touches
  feature-rtl-conversion-and-bitset-library. Cheap cross-ISA benchmark. Platonic
  source.

## Goal

Conway's Life on a fixed grid: seed pattern, run N generations, render ASCII and
print a grid hash per generation. Deterministic by construction.

## Surface / shape

- grid as packed bit rows (`array of` machine words — manual bit packing, or the
  bit-set type once it lands) plus a double-buffer
- neighbor count + B3/S23 rule
- ASCII renderer + a simple grid hash (FNV / sum) per generation

## Coverage

2-D arrays · **bit packing** · integer arithmetic · double-buffering · managed
strings (render). Coverage is shallow (mostly arrays + arithmetic) — value is as
a tiny deterministic oracle + per-target benchmark, not broad surface.

## Acceptance / oracle

- Known patterns behave exactly: a **blinker** oscillates period-2, a **glider**
  translates by (1,1) every 4 generations, still-lifes stay put.
- Fixed seed + N generations → fixed grid hash, byte-identical across targets.
- Demo: `examples/life/` runs a seed for N generations, prints hashes (+ optional
  animation frames over serial).

## Constraints

Platonic source; no compiler changes; ESP32-fit (small grid). No self-host /
cross regression.

## Log
- 2026-06-19 — Opened in the demo-ticket organization pass.
- 2026-06-21 — Conway's Game of Life GUI demo implemented in `examples/life/life.pas`, using the new PCL `TBitmap` offscreen drawing and GTK3 Cairo backend (commit 857a675). Runs in smoke-test mode via `--smoke` flag, compiled and verified in `make demos`.
