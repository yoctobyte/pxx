# Demo — GUI Patience / Solitaire

- **Type:** feature
- **Track:** B
- **Status:** working
- **Owner:** Track B agent (engine-first)
- **Opened:** 2026-06-22
- **Relation:** PCL/widget-set flagship demo. Sibling to
  `feature-demo-solitaire`, which remains the console/line-I/O Klondike ticket.

## Goal

Build a playable GUI patience/solitaire application, starting with Klondike,
under `examples/solitaire_gui/`. The point is not just card-game logic: this is
a practical stress test for the PCL widget set, mouse/keyboard input, repainting,
window resizing, layout, timers, and application-level event flow.

## Scope

- PCL window with a resizable game surface.
- Render stock, waste, foundations, and seven tableau piles with clear card
  faces/backs.
- Mouse interaction: click/drag or click-select/click-drop card moves.
- Keyboard interaction: new game, draw, undo, auto-move to foundation, restart,
  and quit.
- Resize behavior: recompute card sizes, pile spacing, and hit-test regions
  without corrupting state.
- Deterministic seeded shuffles for repeatable tests and bug reports.
- Basic status/score/move counter display.

## Coverage

This should exercise:

- Widget creation, parenting, invalidation, and repaint.
- Mouse down/up/move, keyboard focus/events, and command dispatch.
- Responsive layout and resize notifications.
- Custom drawing, hit testing, and drag/drop state.
- Dynamic arrays / records for deck, piles, move history, and undo.
- Managed strings for labels, status text, and debug/test transcripts.

## Acceptance

- `examples/solitaire_gui/` contains a playable PCL application.
- A deterministic scripted or headless-adjacent test covers at least:
  seeded deal, a few legal/illegal moves, undo, and resize layout recomputation.
- `make gui-test` or a dedicated GUI demo smoke compiles it against
  `$(PXX_STABLE)`.
- Any compiler or missing-widget limitations found during implementation are
  filed as separate Track A/B tickets instead of being hidden in the demo.

## Notes

The first implementation can use click-select/click-drop if drag motion events
are not ready yet. Dragging should remain the desired GUI behavior because it
tests richer mouse event flow and live repaint.

## Log

- 2026-06-22 — Opened on user request for a patience/solitaire GUI app to test
  widget-set behavior, general keyboard/mouse I/O, resizing, and related GUI
  application mechanics.
