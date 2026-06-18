# Demo — Sudoku (solver + generator + interactive play)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18 (from idea-demo-app-candidates — fills the set/bitmask lane)
- **Relation:** companion to feature-demo-chess (chess parked for "rainy
  afternoons" — a proper engine is a project in itself; Sudoku is the smaller,
  earlier real-app test). May consume feature-for-in-iteration once landed.

## Why Sudoku

Passes every demo filter (headless, integer-deterministic, real algorithm,
ESP32-sized, zero authoring — a puzzle is an 81-char string) **and** it exercises
a lane the chess demo barely touches:

- **Sets / bitmasks** — per row/col/box candidate sets (`set of 1..9` or a
  bitmask word). The poster child for set ops; chess uses few.
- **Backtracking recursion** + 2-D arrays + records (grid + constraint state).
- **Exact deterministic oracle** — a well-formed puzzle has a *unique* solution,
  so solved output is byte-exact across all targets; the generator's uniqueness
  check is itself an oracle. No float anywhere.

## Scope — three programs sharing one core

1. **Solver.** Constraint-propagation + backtracking. Input 81-char grid →
   unique solution (or "no/!unique"). The cross-target byte-exact oracle.
2. **Generator.** Build a full solved grid (seeded RNG → deterministic), then
   **strip clues while the puzzle stays uniquely solvable** (remove a cell, run
   the solver's uniqueness test, keep stripping; stop when no further removal
   keeps uniqueness). Seed → reproducible puzzle = deterministic oracle.
3. **Interactive CLI play.** Render the grid, read moves (`r c v`, clear,
   hint via the solver, check), validate against constraints, detect win.
   Line-based stdin/stdout — no curses.

## ESP32 angle

A real **game over serial**: the interactive player built `--esp-profile=bare`
(or IDF), driving the board over UART. First genuinely interactive bare-metal
PXX program — exercises input as well as output on the device. (Bare UART input
path may need a small addition; scope it when reached.)

## Coverage targets (the point — stress the surface)

sets/bitmask · 2-D + dynamic arrays · records · enums · backtracking recursion ·
managed strings (parse/render) · procedural-type or method dispatch (strategy) ·
short-circuit · seeded integer RNG · for-in (once available). Keep the core
integer-deterministic so it doubles as a cross-target regression + benchmark
(solve-time / backtrack-count per ISA).

## Acceptance

- Solver: a published puzzle set solves to the known unique solutions,
  byte-identical across x86-64 / i386 / aarch64 / arm32 (and ESP via UART vs the
  x86-64 oracle).
- Generator: a fixed seed yields a fixed minimal-clue puzzle, reproducible across
  targets; every generated puzzle is uniquely solvable.
- Interactive CLI: scripted stdin transcript → fixed stdout transcript.
- Runs on ESP32 over serial. `make test` integration + cross-bootstrap unaffected.

## Sequence

Language features first (see board). Build after the near-term feature ticks
(`for-in`, explicit casts, any set-op gaps a clean implementation surfaces).
