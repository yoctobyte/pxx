# Demo — console 2048 (screen-lib entertainment + stress test)

- **Type:** feature (Track B — demo / library exercise)
- **Status:** done
- **Owner:** Track B agent
- **Opened:** 2026-06-23
- **Relation:** second consumer of the `screen` TUI manager (after
  console_solitaire) — proves the lib is reusable and surfaces any rendering /
  key-decode bugs. Same shape as the sudoku / solitaire line-UI demos.

## Goal

Playable 2048 in the terminal: a 4x4 grid, arrow keys slide + merge tiles, a new
tile spawns each move, score accumulates, win at 2048, game over when stuck.

## Shape

- Pure engine (`g2048.pas`): global 4x4 grid; `SlideLine` (one testable
  4-cell compress+merge), `Move2048(dir)`, score, win/over predicates, seeded
  spawn. Exhaustively unit-tested apart from the UI.
- UI (`console_2048.pas`): render with `screen.pas`, keys via ScreenWaitKey
  (piped input drives it headlessly; EOF quits) — a scripted smoke in lib-test.

## Acceptance

- Deterministic engine test (slide/merge cases + a seeded move sequence) in
  lib-test; a headless scripted UI smoke. Any compiler/lib bug found → ticket,
  no workaround.

## Log
- 2026-06-23 — **Done.** examples/g2048/g2048.pas (pure engine: SlideLine
  compress/merge, Move2048 along rows/cols, seeded spawn, win/over) + console_2048.pas
  (screen-lib UI, arrow keys, colored tiles, score). Tested: test/lib_g2048.pas
  exhaustive SlideLine + deterministic move/over on ClearBoard/PutTile positions;
  headless UI smoke (seed 1 + a fixed arrow sequence -> score=8). Both in
  make lib-test. Second clean consumer of screen.pas — no lib/compiler bugs
  surfaced this round.

Landed in commit 4198c16.
