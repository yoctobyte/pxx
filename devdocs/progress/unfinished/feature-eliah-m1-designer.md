# Eliah M1 — form designer (box emulation)

- **Type:** feature (app / demo)
- **Status:** unfinished (original box-emulation scope done; component-library scope added, parked — low priority)
- **Track:** B
- **Parent:** feature-eliah-ide
- **Blocked-by:** —
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
- 2026-06-23 — interaction trio DONE: select (docmodel.HitTest, topmost-wins,
  5 bochan gate assertions), drag-move (BeginDrag/DragTo grab-offset), corner-
  resize (HandleAt 4 corners, MIN_SIZE clamp). Selection outline + corner handles
  painted. Inspector pane lists the selected node's Kind/Caption/Left/Top/Width/
  Height, live during drag. All headless-smoke-covered (eliah --smoke).
- 2026-06-23 — OI design refinement: "real RTTI over real *instances*" assumed
  live component instances, but box-emulation has none — the docmodel record is
  the truth. So the inspector reads docmodel fields directly (still render-
  agnostic data; ilja reads the same model). RTTI-over-instances does not apply
  to this architecture; field-list inspector is the correct form.
- Remaining for M1: editable inspector (write a prop back -> repaint), click-to-
  place a new widget from a palette, and seed/load a sample form (.lfm) so the
  surface isn't a hardcoded stub. Then M2 (builder).
- 2026-06-23 — M1 designer COMPLETE. Editable inspector (click a prop row, type,
  Enter -> docmodel write-back via SetNodeCaption/SetNodeBounds, StrToIntDef
  guards bad ints); palette + one-shot click-to-place (KindFromPalette ->
  AddNode parented to form); load: garin/lfmload.LoadLfmText seeds the docmodel
  from apps/ide/eliah/sample.lfm (box-emulation parser, NOT the live-component
  streamer). All headless-smoke + bochan-gate covered (31/31). The pin landmines
  this surfaced (method-ptr coerce, open-array ctor, Length getter, nested
  routines, import-corruption) are all fixed + pinned now; eliah wiring is
  idiomatic. Acceptance met. Remaining IDE work tracked separately:
  feature-eliah-pane-reflow, feature-eliah-m2-builder, and file SAVE (.lfm write).
