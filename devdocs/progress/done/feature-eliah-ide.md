# Eliah / Ilja — single-window IDE (GUI + TUI)

- **Type:** feature (app / demo, supermeta)
- **Status:** done
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

## Tree (final, confirmed 2026-06-22)

```
apps/ide/
  garin/   # core (גרעין = kernel/core): docmodel, buffer, project, builder
  eliah/   # GTK face   (Eliah = Elijah)
  ilja/    # ANSI face  (Ilja  = Elijah)
```

Naming scheme = Hebrew. eliah + ilja both transliterate **Elijah** (the two
faces); **garin** is both a real given name and the word for kernel/core — the
seed both faces grow from. `apps/ide/README.md` carries the one-line decoder.

## Plan (this is the epic; each milestone has its own ticket)

- **M0** → `feature-eliah-m0-window` (taken): Eliah one GTK3 window, tiled layout.
- **M1** → `feature-eliah-m1-designer`: designer paints mock widget boxes.
- **M2** → `feature-eliah-m2-builder`: shell frankonpiler, error list → jump.
- **Later** → `feature-ilja-tui`: ANSI face reusing garin via ansirender.

## Acceptance

M0: Eliah compiles with the pinned stable compiler and opens a single tiled
window. Each later milestone green where it matters (Track B: builds + runs).

## Log
- 2026-06-22 — ticket opened and taken (working/). Design locked with user.

## Closing 2026-07-05

M0 through M5 all shipped (see `devdocs/progress/done/feature-eliah-{m0-window,
m1-designer,m2-builder,layout-tree,pane-reflow,component-palette,perspectives,
selection-link,from-lfm,shell}.md`). Re-verified this session: `apps/ide/build.sh`
builds clean, `apps/ide/test.sh` (headless garin/bochan/eduth gate) 162/162,
`tools/gui_suite.sh` all green including `eliah_ide`, and the built binary opens
a single tiled GTK window under Xvfb with no regressions.

Remaining scope from this epic is tracked in its own tickets, not blocking the
epic itself: **feature-ilja-tui** (the ANSI/TUI face — backlog),
**feature-eliah-pane-header-strip** (labelled collapse strip, filed today),
**feature-eliah-component-tabbar** and **feature-eliah-ai-command-rail**
(backlog). Closing this epic done — Eliah (the GTK face) is a working,
tested IDE; further work continues under the milestone/feature tickets above.
