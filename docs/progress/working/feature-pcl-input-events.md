# PCL: mouse-coordinate + keyboard input events

- **Type:** feature (Track B — PCL widget set)
- **Status:** working
- **Owner:** Track B agent (solitaire-GUI spin-off)
- **Opened:** 2026-06-23
- **Relation:** unblocks the click/drag in `feature-demo-gui-solitaire`, and the
  form designer / hit-testing in `feature-eliah-m1-designer` / `feature-ilja-tui`.

## Why

PCL `TControl` currently exposes only `OnClick` (a coordinate-less notify). Any
app that needs to know *where* the pointer is, which button, or which key — card
drag/drop, a form designer, a canvas editor — cannot be written. Found building
the solitaire GUI, which had to fall back to per-pile buttons.

## Scope

Add to `TControl`, wired from GTK3 signals in `gtk3widgets`:

- `OnMouseDown` / `OnMouseUp` — `procedure(Sender: TControl; Button, X, Y: Integer)`
  from `button-press-event` / `button-release-event` (GdkEventButton: button, x, y).
- `OnMouseMove` — `(Sender; X, Y)` from `motion-notify-event` (with button-mask
  hint for drags; keep it simple first).
- `OnKeyDown` — `(Sender; KeyCode: Integer)` from `key-press-event`
  (GdkEventKey.keyval), plus a few normalized codes (arrows, Enter, Esc).

Mirror the existing `OnClick` wiring (`SignalConnectData(h, 'clicked',
@ControlClickTramp, ...)` + a trampoline that fetches the handler and dispatches).
A widget must request the relevant GdkEventMask (button/pointer-motion/key) and,
for keys, be focusable.

## Coverage / test

- `test/gui/test_pcl_input.pas` (gui-suite): assign handlers, synthesize events
  (gtk/gdk event injection where available, otherwise call the dispatch path with
  a built GdkEvent) and assert the handler ran with the right button/coords/key.
  Compile + headless run like the other gui tests.

## Acceptance

- A control receives mouse down/up/move with correct button + (x,y) and key-down
  with a key code; handlers fire through the same TMethod mechanism as OnClick.
- The solitaire GUI can be reworked to click/drag (separate ticket/update); the
  gui suite stays green.

## Notes

- Coordinate with the Eliah/Ilja agents — `controls.pas` + `gtk3widgets.pas` are
  shared. Keep changes additive (new fields/signals), commit in small units, sync
  often.

## Log
- 2026-06-23 — opened + taken, spun off from the solitaire GUI's PCL-input gap.
- 2026-06-23 — **Mouse events landed.** TControl.OnMouseDown / OnMouseUp /
  OnMouseMove (`procedure(Sender; Button, X, Y: Integer) of object`), wired in
  gtk3widgets from button-press / button-release / motion-notify on the PaintBox
  (gtk_widget_add_events mask 772). Dispatch via a new CallMouseMethod asm
  trampoline (rdi=Self, rsi=Sender, edx=Button, ecx=X, r8d=Y); coords/button read
  through gdk_event_get_button / gdk_event_get_coords. Verified end to end by
  test/gui/test_pcl_input.pas: a synthesized GdkEventButton emitted via
  g_signal_emit_by_name reaches the handler with button=1, x=42, y=17. gui-suite
  green. NEXT: OnKeyDown (key-press-event + keyval), wiring mouse on all controls
  (not just PaintBox) + can-focus for keys, then rework solitaire to click/drag.
