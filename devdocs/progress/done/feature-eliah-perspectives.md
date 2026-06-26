# feature: Eliah perspectives — saved layouts (Code / Design / Split) + compacting

- **Type:** feature (Track B)
- **Status:** done
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

## Progress 2026-06-24

DONE: Code / Design / Split presets as collapse configs of the pane tree
(midRight = [center | right]): code hides right, design hides center, split shows
both. Wired to the View menu + a startup flag (--code/--design/--split) for
screenshot verification. Code + Design screenshot-confirmed on Xvfb :99; Split is
the no-collapse baseline (Restore is a no-op when nothing is collapsed) ==
verified M1 layout. Smoke asserts the three collapse states.

PARTIAL / BLOCKED: full pane hiding wanted gtk_widget_hide (TPaned.Collapse), but
that path hits urgent/bug-method-miscompiled-by-context (a method segfaults vs an
identical-body method that doesn't) and urgent/bug-compiler-hang-on-nested-if-in-begin
(compiler infinite-loop). Collapse falls back to position-only (move handle to an
edge) — enough for Code/Design here, but cannot hide a pane whose sibling resists
shrinking (shrink=0). Revisit hide-based collapse + the remaining M3 scope
(serialized descriptors, per-pane min/priority, priority-compacting on resize)
once the two codegen tickets land.

## Update 2026-06-24 (v48)

UNBLOCKED + DONE for presets: the two codegen bugs were fixed by sis
(v47 Length-of-dynarray-call-result; v48 local-var-shadows-method, which was the
root of both bug-method-miscompiled-by-context and the compiler-hang). TPaned.Collapse
now uses robust gtk_widget_hide full-collapse. All three perspectives
screenshot-confirmed on Xvfb :99: code (right hidden), design (center hidden),
split (all three columns). gui_suite test_pcl_paned covers strip + full collapse.

Remaining M3 scope (separate): serialized perspective descriptors, per-pane
min/priority, priority-compacting on resize. Presets + switcher shipped.

## DONE 2026-06-24

garin/perspective.TPerspective (render-agnostic, bochan-tested 116 asserts):
named layout, per-pane min/priority/visibility, Compact(available) priority
auto-collapse, text round-trip. Eliah drives its horizontal layout through it:
- 3 presets (Code/Design/Split) via View menu + --code/--design/--split flags
  (Code+Design+Split screenshot-confirmed on Xvfb :99);
- priority compacting on every resize (narrow window auto-collapses the
  lowest-priority column = designer, instead of squashing the editor) — proven
  by smoke (ApplyLayout(400) drops right, widening restores) + bochan;
- descriptors round-trip via SaveToText/LoadFromText.
Mode is pure layout (no DesignMode branching). gui_suite + garin(116) green.
