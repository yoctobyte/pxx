# Demo — maze generator + solver

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19
- **Relation:** demo-class candidate from idea-demo-app-candidates (top-10).
  **Pressures the set lane** (visited-set) — see feature-language-gaps-from-demos
  Gap 1. ASCII-over-serial, like the sudoku game. Platonic source.

## Goal

Generate a maze from a seed (recursive-backtracker / Prim), then solve it
(BFS / DFS / A*), rendering both as ASCII. Seed → reproducible maze + path.

## Surface / shape

- grid of cells with wall bitflags (`set` of directions, or a bitmask)
- generator: seeded PRNG (app-local, as in the sudoku game) carving passages
- solver: BFS/A* over the grid — queue / priority collection
- ASCII renderer (managed strings)

## Coverage

2-D arrays · **sets** (visited cells / wall directions — the runtime set lane) ·
collections (frontier queue / priority) · recursion or explicit stack ·
seeded integer PRNG · managed strings (render). Integer-deterministic.

## Acceptance / oracle

- Fixed seed → fixed maze layout + fixed solution path length, byte-identical
  across targets.
- Demo: `examples/maze/` prints the maze and the solved path; optional
  interactive "walk it" mode over serial.

## Constraints

Platonic source; no compiler changes; ESP32-fit (tune grid size per target). No
self-host / cross regression.

## Log
- 2026-06-19 — Opened in the demo-ticket organization pass.

## Status 2026-06-19 (track B, v10)

Compiles on v10 and **Generate + Render work** (prints the maze). **`Solve`
(BFS) segfaults at runtime** — isolated: replacing the `Solve` call with a
constant renders fine; a minimal function with the same large 2-D static-array
locals does NOT crash, so it's specific to Solve's BFS/path logic (a subtle OOB
on my side, or a context-sensitive codegen issue — no clean standalone repro
yet). In `demos` it shows compile-OK; runtime solve is the open item. Revisit
with gdb / step-through once there's time; not a clean track-A ticket yet.
