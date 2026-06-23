# Eliah — pane reflow / resizable splitters

- **Type:** feature (app / demo)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-ide
- **Blocked-by:** feature-eliah-m0-window
- **Opened:** 2026-06-22

## Motivation

M0 lays panes with absolute `gtk_fixed` bounds. The window is resizable but panes
do not reflow, and there are no drag-splitters between panes. The IDE wants the
tiled panes to track the window size (single sizable window — the whole point).

## Options

- Recompute pane bounds on window size-allocate and re-`SetBounds` each pane
  (keeps gtk_fixed; needs a resize signal hook in PCL — may be a PCL gap).
- Add real `GtkPaned` (HPaned/VPaned) support to PCL for drag-splitters
  (bigger; benefits all PCL apps). If PCL can't express it → still app-side, but
  a PCL feature ticket may be the cleaner route.

## Acceptance

Resizing the Eliah window reflows the panes to fill it; (stretch) draggable
splitters between panes. No modal/subwindows introduced.

## Log
- 2026-06-22 — filed from M0 caveat (absolute bounds, no reflow).
- 2026-06-23 — DONE (core). Took option 1: wired 'size-allocate' on the form's
  fixed container in pcl/gtk3widgets so TForm.OnResize fires with the content
  w/h (was a real PCL gap — only TPaintBox had it). eliah Relayout(w,h)
  recomputes all pane bounds on resize, clamped for tiny windows. Smoke-covered;
  full gui_suite green. STRETCH not done: draggable GtkPaned splitters — left as
  a separate future enhancement (bigger, benefits all PCL apps).
