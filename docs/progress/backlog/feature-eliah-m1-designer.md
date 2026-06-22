# Eliah M1 — form designer (box emulation)

- **Type:** feature (app / demo)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-ide
- **Blocked-by:** feature-eliah-m0-window
- **Opened:** 2026-06-22

## Goal

Designer pane paints a designed form as **plain drawn boxes** — pure emulation,
NO live widget instantiation, no design-time/runtime `TComponent` split, no
`TComponent` linked. Each box shows widget kind + caption + estimated px size.

## Scope

- `apps/ide/garin/docmodel.pas` — widget-tree doc: nodes (kind, caption, x/y/w/h
  in px, children), render-agnostic. Serialization later.
- `apps/ide/eliah/designer.pas` — GTK DrawingArea, paints docmodel via
  `lib/pcl/graphics.pas` TCanvas: rectangle + label + size text per node.
- Interaction: click-place a widget, drag to move, drag handles to resize;
  selection outline. Property edits land in the props pane (inline, no modal).

## Acceptance

Place/move/resize mock widgets on the canvas; docmodel updates; repaint matches.
Coords px (GUI-native). No real GTK widget is instantiated for the preview.

## Log
- 2026-06-22 — filed (depends on M0).
