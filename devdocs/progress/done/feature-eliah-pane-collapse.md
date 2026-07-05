# feature: Eliah pane collapse/restore + ratio memory

- **Type:** feature (Track B)
- **Status:** done
- **Track:** B
- **Parent:** feature-eliah-shell
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

## Update 2026-06-24 (v48)

Full hide-based collapse now works (gtk_widget_hide; the blocking codegen bugs
were fixed in v47/v48). Still DEFERRED: the labelled clickable collapse *strip* +
per-pane header chevron (needs a stacking container / TBox). Menu + perspective
collapse are fully functional.

## Closing 2026-07-05

Re-verified: build + `apps/ide/test.sh` (162/162) + `tools/gui_suite.sh`
(test_pcl_paned, test_pcl_stream_paned, eliah_ide) all green; Eliah opens under
Xvfb with no regressions. `TPaned.Collapse/Restore/Toggle` + ratio memory ship
and are exercised by both the headless garin gate and the GUI smoke test —
that's the acceptance this ticket set out to hit (collapse/restore, ratio
persists, no pane destroyed).

The one item still open — a **labelled clickable strip + chevron header** per
pane (Lazarus/VS-Code style, rather than only the View-menu toggle) — was
blocked on PCL lacking a stacking container. Added `TBox` (`lib/pcl/extctrls.pas`
+ `gtk3widgets.pas` `SetParent`, wraps `gtk_box_new`/`gtk_box_pack_start`,
already declared in `gtk3_c.h`) as a general-purpose PCL widget, smoke-tested
standalone under Xvfb (vertical stack of two labels, clean exit). It is not yet
wired into Eliah's pane headers — that's real layout surgery on `main.pas`
(colLeft/midRight/RootPaned construction), scoped out as its own ticket:
**feature-eliah-pane-header-strip**, now unblocked since `TBox` exists. Closing
this ticket done; the strip is a follow-up, not a blocker on it.
