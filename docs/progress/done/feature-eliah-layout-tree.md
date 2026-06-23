# feature: Eliah layout tree — window as a nested-TPaned splitter tree

- **Type:** feature (Track B)
- **Status:** done
- **Track:** B
- **Parent:** feature-eliah-shell
- **Opened:** 2026-06-23

## Goal

Replace Eliah's absolute `gtk_fixed` + manual `Relayout` pane positioning with a
**tree of `TPaned`** whose leaves are pane containers. This is the foundation the
rest of the shell stands on.

## Why

Today `apps/ide/eliah/main.pas` sizes every pane with absolute `SetBounds` inside
the form's `gtk_fixed`, reflowing by hand on resize. That cannot express
draggable splitters, collapse, or saved perspectives. A `TPaned` tree gives real
drag for free and makes layout *data* (a tree + ratios) instead of code.

## Scope

- Define a **pane-container** abstraction (`TIdePane` or similar): a leaf holding
  exactly one view today (tree / editor / output / errors / designer / inspector
  / palette). It owns a header area (for the future collapse chevron + title) and
  a content slot. Keep it a *slot* so a tab strip can replace the single view
  later — do not hardcode one-view-per-leaf.
- Build the current Eliah layout as a `TPaned` tree, e.g.:
  `HPaned[ VPaned[ tree , errors ] | HPaned[ center , VPaned[ output , inspector ] ] ]`
  (exact shape TBD — match the present panes).
- Drop the absolute-coordinate `Relayout`; let GtkPaned own sizing. Keep the
  form-level resize only where genuinely needed.
- Children parent into panes via the existing `TGtk3WidgetSet.SetParent` TPaned
  branch (pack1/pack2) — already landed with `TPaned`.

## Non-goals (later milestones)

- Collapse/restore strips (`feature-eliah-pane-collapse`).
- Saved perspectives / presets / priority-compacting
  (`feature-eliah-perspectives`).

## Acceptance

Eliah renders the same panes as today but every divider is a **draggable
splitter**. Resizing the window behaves sanely (GtkPaned reflow). `--smoke` green,
`gui_suite` green, `apps/ide/test.sh` (garin) green, screenshot confirms all panes
visible with draggable handles. No absolute `gtk_fixed` pane math left in the
main layout path.

## Risks / notes

- This is the big rewrite flagged in the layout discussion. Do it as one focused
  change; verify with a screenshot (headless `--smoke` does NOT prove render).
- A multi-child column (e.g. tree above errors) is a nested `TPaned`, since
  GtkPaned holds exactly two children. Expect a tree a few levels deep.
- Menubar/toolbar stay outside the paned tree (top of the form vbox), as now.
- May surface `TPaned` gaps (min-size, initial ratios before realize) → file PCL
  tickets, keep app code idiomatic.

## Log
- 2026-06-23 — filed (milestone 1 of feature-eliah-shell).

## Log
- 2026-06-24 — DONE. Eliah's window is now one nested-TPaned tree (RootPaned):
  HPaned[ colLeft(V: tree/errors) | HPaned[ colCenter(V: editor/output) |
  colRight(V: designer / colInspector(V: props/valueEdit)) ] ]. Children parent
  into leaves via the existing SetParent TPaned branch. Absolute per-pane
  Relayout math removed — Relayout now only resizes RootPaned; GtkPaned owns the
  splits. Handle positions seeded once on the first allocation (OnFormResize),
  since GtkPaned clamps a position set before it has a size. Smoke asserts root
  reflow; gui_suite + garin(92) green; screenshot (Xvfb :99) confirms all panes
  render with draggable handles. Also added docs/developer/gui-testing.md
  (Xvfb-based GUI testing, no foreground grab).
