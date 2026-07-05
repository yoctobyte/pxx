# feature: Eliah pane header — labelled collapse strip + chevron

- **Type:** feature (Track B)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-shell
- **Depends-on:** none (PCL `TBox` landed 2026-07-05)
- **Opened:** 2026-07-05

## Goal

Give every pane a small header (title + collapse chevron ▾/▸) so a pane can be
collapsed/restored by clicking its own header — Lazarus/VS Code tool-window
style — instead of only through the View menu.

## Why

Split out of `feature-eliah-pane-collapse` (closed done 2026-07-05): the
underlying collapse/restore/ratio-memory mechanics (`TPaned.Collapse` et al.)
shipped and are menu-driven today. The labelled clickable strip was deferred
because PCL had no stacking container to build a header row with; that
container (`TBox`, `lib/pcl/extctrls.pas`) now exists and is smoke-tested.

## Scope

- Wrap each leaf pane's existing content widget in a `TBox` (Vertical): header
  row on top (a `TLabel` for the title + a small button/label acting as the
  chevron), original content below.
- Header click (or chevron click) calls the existing `TPaned.Toggle` for that
  pane — no new collapse mechanics needed, just wiring click → the API that
  already ships.
- When collapsed, the header itself becomes the visible strip (shrink content
  to 0 via the existing full-hide path; the header row stays visible at its
  natural size).
- Touches `apps/ide/eliah/main.pas` layout construction (colLeft / midRight /
  RootPaned) — real surgery on a shipped, tested file; build incrementally, run
  `apps/ide/test.sh` + `tools/gui_suite.sh` (`eliah_ide`) after each step so a
  regression is caught immediately, not at the end.

## Acceptance

Each pane shows a header with a chevron; clicking it collapses to a thin
labelled strip; clicking again restores the previous ratio. `gui_suite` +
`apps/ide/test.sh` green; Xvfb screenshot shows one collapsed strip + the rest
of the layout intact.

## Log
- 2026-07-05 — filed, split out of feature-eliah-pane-collapse now that its
  dependency (PCL `TBox`) is unblocked.
