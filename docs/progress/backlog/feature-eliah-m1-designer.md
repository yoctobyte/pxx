# Eliah M1 — form designer (box emulation)

- **Type:** feature (app / demo)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-ide
- **Blocked-by:** feature-eliah-m0-window
- **Opened:** 2026-06-22

## Goal

Designer pane paints a designed form as **plain drawn boxes** — pure emulation.
Each box = a rectangle with widget kind + caption + size. The garin docmodel is
the **source of truth** (serializes to .lfm/.pas, and is what ilja renders too).

**Live widgets REJECTED (2026-06-23, user):** no instantiation of pcl/GTK
controls for the preview — they overcomplicate, can bug up, and ilja can't share
them anyway. Box emulation only. Still: no design-time/runtime `TComponent`
split, no `TComponent` linked, no design-time packages.

## Scope

- `apps/ide/garin/docmodel.pas` — widget-tree doc: nodes (kind, caption, parent,
  x/y/w/h in px, children), render-agnostic. The truth; serialization later.
  Most-used props are deliberately few: **width + height + parent** cover ~9/10
  cases; **caption** for labels/buttons. Keep the node minimal.
- `apps/ide/eliah/designer.pas` — GTK DrawingArea, paints docmodel via
  `lib/pcl/graphics.pas` TCanvas: rectangle + label + size text per node.
- **Object inspector via real RTTI** (`lib/rtl/typinfo.pas`): inspect a real
  instance's published props (render-agnostic *data* — ilja shows the same).
  Editing a prop updates the docmodel; designer repaints. Inline in props pane,
  no modal.
- Interaction: click-place, drag move, drag handles to resize; selection outline.

## Acceptance

Place/move/resize mock boxes on the canvas; docmodel updates; repaint matches.
OI lists a node's props from RTTI and edits write back to the docmodel. Coords px.
No live GTK widget instantiated for the preview. Builds with `$(PXX_STABLE)`;
compiler gaps → Track A ticket, no workaround.

## Log
- 2026-06-22 — filed (depends on M0).
- 2026-06-23 — locked: box emulation ONLY (live-widget view rejected by user);
  docmodel = source of truth; OI via real RTTI over real instances (render-
  agnostic data, shared with ilja); minimal node = width+height+parent (+caption
  for label/button).
