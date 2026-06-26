# Demo — GUI Patience / Solitaire

- **Type:** feature
- **Track:** B
- **Status:** done
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

## Log
- 2026-06-23 — Engine-first landed: `examples/solitaire_gui/klondike.pas` (pure
  logic, fixed 2D-array board, pure move predicates, seeded deal, draw/recycle,
  multi-card runs, auto-to-foundation, win, full undo). Tested by
  `test/lib_klondike.pas` in `make lib-test` (exhaustive predicates + move/undo
  checksum round-trips).
- 2026-06-23 — GUI front-end landed: `examples/solitaire_gui/solitaire_gui.pas`
  (PCL/GTK3): board custom-drawn in TPaintBox.OnPaint, button-driven play
  (New/Draw/Undo/Auto/To-Found + pile-select). `--smoke` headless integration
  check wired into `tools/gui_suite.sh` (renders + a few engine moves, SMOKE OK).
  LIMITATION: play is button-driven because PCL exposes only OnClick (no mouse
  coordinates/keys) — the ticket's click/drag + keyboard needs PCL mouse/key
  events first (a PCL/widget-set extension, not this demo). Discovered building
  this; flag for the PCL track.
- 2026-06-23 — **Click-to-play landed** on the new PCL mouse events
  (feature-pcl-input-events). The board is now interactive: PaintBox.OnMouseDown
  -> HitPile(x,y) maps the click to a pile (mirrors the OnPaint layout); clicking
  the stock draws, clicking a source then a destination (tableau or foundation)
  moves the largest legal run. Pile-select buttons removed; only New/Undo/Auto
  remain. The `--smoke` now drives DoMouseDown directly and asserts a stock click
  draws a card. gui-suite green. REMAINING (polish): true drag/drop (vs
  click-select-click-drop), window-resize relayout, score/move counter.
- 2026-06-23 — **Feature-complete.** Drag/drop (press source / release dest),
  keyboard shortcuts (n/u/a/d/q), move counter + win in the status label, and
  responsive resize (RecalcLayout from OnResize: card size / spacing / hit-test
  scale with the window). Plus undo, seeded New, auto-to-foundation. Engine in
  lib-test; GUI smoke (draw/drag/key/resize asserts) in gui-suite. Closing.

Landed in commits 675b492 (engine), 41044fc (GUI), e2b4f53 (click), cb40753
(drag/keyboard/counter), 234de84 (responsive resize).
