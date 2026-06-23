# feature: Eliah perspectives — saved layouts (Code / Design / Split) + compacting

- **Type:** feature (Track B)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-shell
- **Blocked-by:** feature-eliah-layout-tree, feature-eliah-pane-collapse
- **Opened:** 2026-06-23

## Goal

Make layout **data**: a perspective = a serialized splitter tree + per-pane
ratio/min/priority/visibility. Ship three presets — **Code**, **Design**,
**Split** — switchable from the toolbar. Resizing compacts predictably.

## Why

The three "modes" the user wants are not app states with branches — they are
three saved trees. Building them as data kills the awkward Delphi "mode" feeling
and makes Split view free.

## Scope

- **Perspective descriptor**: serialize the splitter tree (node = H/V split +
  ratio; leaf = pane id) plus, per pane, `min-size`, `priority`, `visible`.
  Reuse the `.pxxproj`-style line/section format or a small binary — round-trips.
- **Presets**: Code (tree + editor + console, designer hidden), Design (forms
  list + designer + inspector + palette, editor hidden), Split (both, editor |
  designer side-by-side). Each is a descriptor, loaded on switch.
- **Switcher**: toolbar segmented control / 3 buttons. Switching loads the
  descriptor and reflows; current pane sizes optionally remembered per
  perspective.
- **Compacting on resize**: distribute space by ratio, clamp each pane to its
  min-size; when `available < sum(mins of visible panes)`, **auto-collapse the
  lowest-priority pane** (using milestone 2's collapse) until it fits. Never
  squash everyone below min.
- User edits to a perspective (drag splitters, collapse) persist for that
  perspective.

## The one rule

A perspective only sets visibility + tree + ratios. **No `if DesignMode`
branching in logic.** Editor, designer, project, selection all stay live
regardless of which perspective is shown.

## Acceptance

Three preset buttons switch layouts with no window/dialog; each shows the right
panes; dragging/collapsing within a perspective persists; shrinking the window
clamps to mins and auto-collapses by priority rather than squashing; descriptors
round-trip through save/load. `gui_suite` + garin green; screenshots of all three
presets + a compacted (auto-collapsed) state.

## Log
- 2026-06-23 — filed (milestone 3 of feature-eliah-shell).
