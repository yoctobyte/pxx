# Eliah / Ilja — single-window IDE (GUI + TUI)

- **Type:** feature (app / demo, supermeta)
- **Status:** working
- **Track:** B (built with `$(PXX_STABLE)`; never rebuilds the compiler)
- **Owner:** Track B agent
- **Opened:** 2026-06-22

## Motivation

A graphical (GTK) and TUI (ANSI) IDE, Lazarus/Delphi-inspired but deliberately
stripped: single sizable window, **no multi-window, no modal forms, no scattered
subwindows** — everything tiled in one window. Codenames: **Eliah** = GUI
(posix+gtk), **Ilja** = CLI/TUI (posix + ANSI). They share render-agnostic data
models; rendering/input/layout is reimplemented per target at micro scale.

This is a real-world test case for the compiler **on purpose**: PXX crafts it,
dialect features welcome (no FPC-compat constraint). Compiler gaps that *should*
work → file a Track A ticket, **no workarounds**. App may depend on any of our
libraries (`lib/rtl`, `lib/pcl`); it is supermeta to the compiler.

## Design decisions (locked with user 2026-06-22)

- **Coords:** px, GUI-native. Focus GUI first; keep TUI sharing in mind.
- **Form preview:** pure emulation — plain drawn boxes with content + estimated
  size. **No live widget instantiation**, no design-time/runtime `TComponent`
  split, no `TComponent` linked.
- **Dialogs:** plain rectangular panels inside the app window. No modal forms.
- **Shared (render-agnostic):** editor buffer, project tree, widget-tree (the
  designed-form doc), error list.
- **Forked per target:** rendering, input, layout. Canvas already exists both
  worlds — `lib/pcl/graphics.pas` (GTK) + `lib/rtl/ansirender.pas` (ANSI).

## Proposed tree (naming pending final OK)

```
apps/
  ide/      # shared, render-agnostic models
  eliah/    # GTK frontend (build now)
  ilja/     # TUI frontend (later)
```

## Plan

- **M0 (now):** Eliah — one GTK3 window, fixed tiled layout (proj tree | editor |
  designer | output/props), editor pane live, rest stub. Build w/ `$(PXX_STABLE)`,
  run, screenshot. Proves window + layout + dogfood path.
- **M1:** designer pane paints mock widget boxes from the widget-tree model;
  click-place, drag move/resize.
- **M2:** builder shells to frankonpiler, error list → editor jump.
- **Later:** Ilja TUI frontend reusing the shared models via ansirender.

## Acceptance

M0: Eliah compiles with the pinned stable compiler and opens a single tiled
window. Each later milestone green where it matters (Track B: builds + runs).

## Log
- 2026-06-22 — ticket opened and taken (working/). Design locked with user.
