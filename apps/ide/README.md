# apps/ide — the Eliah / Ilja IDE

A single-window IDE, Lazarus/Delphi-inspired but deliberately stripped: one
sizable window, **no multi-window, no modal forms, no scattered subwindows**.
Everything lives tiled in one window.

## Naming (Hebrew)

- **garin** (גרעין) = *kernel / core*. The render-agnostic engine: editor buffer,
  project model, the designed-form document, the builder. Both faces grow from
  this seed.
- **eliah** = *Elijah* (GTK face — posix + GTK).
- **ilja** = *Elijah* again, a second transliteration (ANSI/TUI face — posix +
  terminal). Same prophet, two faces; same product, two renderers.

```
apps/ide/
  garin/   # core — shared, render-agnostic
  eliah/   # GTK face   (build first)
  ilja/    # ANSI face  (later)
```

## Hard rules

- **Pure box emulation** for form preview: the designer paints plain boxes with
  content and an estimated size. It does **not** instantiate live widgets, and we
  do **not** compile design-mode components into the IDE. No design-time/runtime
  `TComponent` split, no `TComponent` linked.
- GUI and TUI have different requirements: only the **data models** (garin) are
  shared. Rendering, input, and layout are reimplemented per face.

## Build (Eliah, M0)

```sh
apps/ide/build.sh        # uses the pinned stable compiler
apps/ide/eliah/eliah     # run
```
