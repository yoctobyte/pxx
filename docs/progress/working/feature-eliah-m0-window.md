# Eliah M0 — single tiled GTK3 window

- **Type:** feature (app / demo)
- **Status:** working
- **Track:** B (built with `$(PXX_STABLE)`)
- **Owner:** Track B agent
- **Parent:** feature-eliah-ide
- **Opened:** 2026-06-22

## Goal

Prove the dogfood path + window shell. One GTK3 window, fixed tiled layout, no
modal/subwindows. Editor pane live; other panes stubbed. Compile with the pinned
stable compiler, run, screenshot.

## Scope

- `apps/ide/garin/` — first render-agnostic stubs only as needed (editor buffer
  interface, project model placeholder). Keep faces out.
- `apps/ide/eliah/main.pas` — single `TForm`/window via `lib/pcl`:
  - tiled 4-pane layout: **proj tree | editor | designer | output/props**.
  - resizable splitters, NO floating/modal/subwindows.
  - editor pane: live text view backed by garin buffer (open/edit one file).
  - other panes: visible stubs (labels/placeholder boxes).
- `apps/ide/README.md` — naming decoder (garin/eliah/ilja).
- Build wiring: invokable with `$(PXX_STABLE)` (Makefile target or script).

## Non-goals (later milestones)

- Form designer painting (M1). Builder integration (M2). Ilja/TUI.

## Acceptance

- `apps/ide/eliah` compiles with `$(PXX_STABLE)` — zero workarounds.
- Running opens ONE window with the tiled layout; editor pane loads + edits a
  file; splitters resize; no extra windows pop.
- Screenshot captured.
- Any compiler gap hit → Track A ticket filed, referenced here. No workaround.

## Log
- 2026-06-22 — opened + taken. First code slice of the IDE.
