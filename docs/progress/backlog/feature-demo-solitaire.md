# Demo — console Klondike solitaire (user-requested entertainment test app)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19 (user-called: "as user, I am calling solitaire")
- **Relation:** demo-class, but a deliberate **exception to the catalog's
  headless / pure-oracle filter** in idea-demo-app-candidates — admitted because
  it is the most *entertaining* test app for a human tester on a Linux host.
  Distinct from the rejected visual/audio "please-user" demos (ray-tracer /
  Mandelbrot / chiptune): solitaire is text + stateful logic, not a pixel/audio
  toy. Shares the line-UI shape of the sudoku game.

## Goal

Playable Klondike solitaire in the terminal: shuffle a seeded deck, deal the
tableau, and let a human play (draw, move runs, send to foundations) until win.

## The ncurses / ESP32 question (resolved)

- **No ncurses binding.** ANSI escape codes are just bytes written to stdout
  (`ESC[2J` clear, `ESC[r;cH` cursor) — render via plain managed strings, no C
  library, no header import. Keeps the dependency story clean.
- **Input:** raw single-key input needs `termios` (a small platform dep). Avoid
  it by default with **line commands** (e.g. `d` draw, `m ws t3` waste→tableau 3,
  `m t1 f` tableau 1→foundation, `u` undo, `n` new, `q` quit). Line I/O is fully
  portable and works over **ESP32 serial**, so the demo is *not* ESP-excluded.
- Optional later: an ANSI full-screen + raw-key layer (this is where a small
  **TUI helper library** could eventually be spun out — note it, do not ticket
  it yet).

## Surface / shape

- enums: suit (♣♦♥♠ / CDHS), rank (A..K), color
- record `TCard` (suit, rank, faceUp)
- piles: stock / waste / 4 foundations / 7 tableau columns — **dynamic-array
  stacks**, the natural data structure stress
- seeded PRNG shuffle (app-local, as in the sudoku game)
- move validation (alternating-color descending tableau, ascending same-suit
  foundations), undo stack (records)
- renderer: ASCII board (plain) or ANSI (optional)

## Coverage

enums · records · dynamic arrays as stacks (push/pop heavy) · managed strings
(render + command parse) · state machine + move legality (short-circuit) · seeded
integer PRNG · undo (record history). Solid mid-size surface; integer-only.

## Acceptance / oracle (the honest caveat)

Interactive → weaker oracle than chess/perft. Pin it down with:
- **Seeded deal is reproducible:** seed → exact initial layout, byte-identical
  across targets.
- **Scripted transcript:** a fixed stdin move sequence → fixed final board /
  "you win" output (same harness shape as the sudoku-game scripted test).
- Optional: an **auto-play solver** for a seed → deterministic solvable/stuck
  verdict (a real oracle if added).
- Demo: `examples/solitaire/` — interactive on a Linux host; scripted transcript
  in `make test`.

## Constraints

Platonic source; no compiler changes; no ncurses. Primary target = Linux host
entertainment; ESP-serial via line mode. No self-host / cross regression.

## Log
- 2026-06-19 — Opened on user request. Resolved the ncurses worry up front (ANSI
  = strings, line-input avoids termios) so the demo stays dependency-free and
  ESP-serial-capable; flagged the oracle caveat + the seeded-deal / scripted
  transcript test hooks.
