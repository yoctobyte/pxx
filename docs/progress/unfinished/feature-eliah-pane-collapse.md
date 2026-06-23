# feature: Eliah pane collapse/restore + ratio memory

- **Type:** feature (Track B)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-shell
- **Blocked-by:** feature-eliah-layout-tree
- **Opened:** 2026-06-23

## Goal

Let any pane **collapse to a thin clickable strip and restore** to its previous
size. Collapse must never destroy the pane or forget its ratio.

## Why

"UI should be fine setting a splitter to extremes." Drag-to-zero loses a pane and
is fiddly. Explicit collapse (IntelliJ tool-window stripe / VS Code activity bar)
is predictable: one click hides, one click brings it back exactly where it was.

## Scope

- Pane header gets a **collapse chevron** (▾/▸). Clicking collapses the pane:
  store its current splitter ratio, then set the handle to the edge so the pane
  shrinks to a thin **strip** showing its title (rotated/short) + chevron.
- Clicking the strip (or chevron) **restores** the remembered ratio.
- A collapsed pane stays in the tree (still a leaf); only its visible size goes to
  the strip width. No reparenting, no destruction.
- Keep `GtkPaned` `shrink=0` (min-size respected during normal drag); collapse is
  the *explicit* path to zero, distinct from dragging.

## Acceptance

Each pane can be collapsed and restored via its header; the restored size equals
the pre-collapse ratio; a collapsed pane shows a labelled strip and survives
window resizes. `gui_suite` + garin green; screenshot shows a collapsed strip and
a restored pane.

## Notes

- Likely needs a small `TPaned` capability: read/set handle position as a ratio
  and a "collapse to edge" helper, plus a per-pane stored ratio. If `TPaned` can't
  express it cleanly, extend the PCL widget (Track B owns lib/pcl) — keep it
  general so all PCL apps benefit.
- The strip is itself a tiny pane-header view; reuse the header abstraction from
  `feature-eliah-layout-tree`.

## Log
- 2026-06-23 — filed (milestone 2 of feature-eliah-shell).

## Progress 2026-06-24

CORE DONE: TPaned.Collapse/Restore/Toggle (remembers handle position) +
gui_suite coverage; Eliah View menu toggles Left/Output/Right panels.

DEFERRED: the labelled clickable collapse *strip* + per-pane header chevron need
a stacking container (gtk_box / a PCL TBox with per-child expand) that PCL does
not yet expose. Functional collapse/restore ships via the menu meanwhile.
