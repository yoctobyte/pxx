# feature: Eliah pane header — labelled collapse strip + chevron

- **Type:** feature (Track B)
- **Status:** done
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

## Done 2026-07-05

Shipped with a simpler header widget than originally scoped: a full-width
`TButton` per pane (caption = chevron char + title, e.g. `v Project` /
`> Project`) instead of a separate label+chevron pair — reuses the exact
button+`OnClick` pattern already used by every other control in this file, no
new event wiring needed. Chevron flips `v`/`>` on toggle to show open/closed
state (plain ASCII, not the unicode ▾/▸ glyphs originally proposed — simpler
and avoids any font/encoding risk in the `.lfm` text format).

**TBox gained the packing rule this needed:** first child packed into a
`TBox` keeps its natural size (the header), every child packed after it
expands/fills the remaining space (`lib/pcl/gtk3widgets.pas` `SetParent`,
using `gtk_container_get_children`/`g_list_length` — both added to
`gtk3_c.h` — to detect "is this the first child"). This is a general TBox
rule, not Eliah-specific, so future TBox users get header-then-content
layout for free.

**Wired in `apps/ide/eliah/eliah.lfm`:** `leftBox`/`rightBox`/`outputBox`
(`TBox`, Vertical) each wrap a header `TButton` + the pre-existing pane
content (`colLeft`, `colRight`, `Output`) — the existing named objects are
untouched, just nested one level deeper; name-based `.lfm` streaming binds
through the extra nesting with no changes needed to the binder. Header
`OnClick` reuses the existing `OnToggleLeft`/`OnToggleRight`/`OnToggleOutput`
handlers verbatim — no new collapse mechanics, exactly as scoped.

Fixed one bug caught before commit: `OnToggleOutput` read
`colCenter.CollapsedPane` unguarded after the existing `if colCenter <> nil`
check on the line above it — unreachable in practice (colCenter is always
bound by the time a click can fire) but inconsistent; added the same nil
guard.

Verified: `apps/ide/build.sh` clean, `apps/ide/test.sh` 162/162,
`tools/gui_suite.sh` all green (`eliah_ide` included), Xvfb screenshot
(`tools/gui_shot.sh`) confirms all three header strips render full-width
with correct chevron/title and content still filling the remaining space
correctly.
