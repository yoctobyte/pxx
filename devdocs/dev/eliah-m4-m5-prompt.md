# PROMPT TO SELF — continue Eliah M4 + M5 (Track B, frank2)

You are a **Track B** agent on frank2 / PXX (pascal26), branch `master`, cwd
`/home/rene/frank2`. Goal: keep building **Eliah**, the GTK IDE, into a polished
perspective-based shell. Not bug-hunting — but compiler/lib gaps get a ticket
(**Platonic**: never bend app/lib logic around a gap; minimal repro + ticket +
clean blocked code; Track A / "sis" fixes them fast).

## Hard rules
- Build only with the pinned stable `stable_linux_amd64/default/pinned`. Never
  rebuild the compiler.
- Work on `master`, commit small, `git pull --rebase` before push, push when green.
- Compiler/lib gap → ticket in `devdocs/progress/{urgent,backlog}/`, regen board
  (`tools/progress.sh board-md`).

## CRITICAL lessons (don't repeat past mistakes)
- `--smoke` validates **logic, not GTK render**. ALWAYS screenshot a GUI change:
  `tools/gui_shot.sh /tmp/x.png apps/ide/eliah/eliah --split` then Read it.
  (Runs on Xvfb `:99`, no foreground/HID grab. Knobs: `GUI_SHOT_SIZE`,
  `GUI_SHOT_FRESH=1`. See `devdocs/developer/gui-testing.md`.) No xdotool → can't
  script clicks; verify render via screenshot, interaction via `--smoke`.
- Adding **virtual methods to `lib/pcl/uwidgetset.TWidgetSet` miscompiles their
  object argument** — build new PCL widgets by calling gtk directly via `gtk3_c`
  (like `graphics.pas` and `extctrls.TPaned`). See
  `done/bug-widgetset-virtual-arg-corruption`.
- Screenshot tooling traps (now handled by `gui_shot.sh`): ffmpeg must use
  `-frames:v 1`; a wedged Xvfb yields blank ~1-3 KB PNGs → restart it fresh.

## Build + gates
```
stable_linux_amd64/default/pinned -Fulib/pcl -Fulib/rtl -Fuapps/ide/garin apps/ide/eliah/main.pas apps/ide/eliah/eliah
apps/ide/eliah/eliah --smoke                                   # SMOKE OK
apps/ide/test.sh                                               # garin headless gate (bochan, 116 asserts)
PXX_STABLE=stable_linux_amd64/default/pinned tools/gui_suite.sh  # PCL GUI suite
tools/gui_shot.sh /tmp/e.png apps/ide/eliah/eliah --split      # screenshot (Xvfb)
```

## Architecture (`apps/ide/`)
- `garin/` = render-agnostic core (bochan-tested): `docmodel` (widget tree),
  `lfmload` (.lfm box-emulation parse/serialize), `buffer`, `builder` (diag
  parser), `runner`, `project` (.pxxproj model), `perspective` (layout model +
  priority compacting).
- `eliah/main.pas` = the app: `THandler` + imperative widget setup. The window is
  ONE nested-`TPaned` splitter tree (RootPaned). `designer.pas` = box renderer.
- `lib/pcl` = PCL widgets (`TPaned` has Collapse/Restore/Toggle). `lib/rtl/
  classes_lite` = `TComponent` (virtual `Create(AOwner)`) + the streamer
  (`TReader`).

## Epic + what's DONE
Epic: `devdocs/progress/{backlog,done}/feature-eliah-shell.md` — one window, splitter
tree, **mode = pure layout (no `if DesignMode` branching)**.
- **M1** `feature-eliah-layout-tree` ✅ — window is a nested-`TPaned` tree.
- **M2** `feature-eliah-pane-collapse` ✅ core — `TPaned.Collapse` (full hide via
  `gtk_widget_hide`) + View-menu toggles. DEFERRED: labelled clickable collapse
  *strip* + per-pane header chevron → needs a stacking container (a PCL `TBox` /
  gtk_box with per-child expand), which PCL lacks.
- **M3** `feature-eliah-perspectives` ✅ — `garin/perspective.TPerspective`
  (min/priority/visibility, `Compact()` priority auto-collapse, text round-trip);
  Code/Design/Split presets (View menu + `--code/--design/--split`); compacting
  on resize. Mode is pure layout.

## TODO — M4 and M5

### M4 — `feature-eliah-component-palette` (backlog)
Registry-driven designer palette: a component is any `RegisterClass`'d
`TComponent` with published RTTI — visual widgets AND non-visual libraries are
the same thing.
- Enumerate registered classes (reuse the `GetClass`/RTTI registry the streamer
  uses). Palette pane lists them, grouped.
- Drop: visual → onto the form surface (today's path); **non-visual → a tray
  strip along the form bottom** (Delphi-style icon tray), editable in the
  inspector via published RTTI.
- **Dependency now satisfied:** `bug-metaclass-new-getclass-vmt` was FIXED (v46),
  so `TComponentClass(GetClass(name)).Create(AOwner)` constructs with a canonical
  VMT. So **the streamer adoption is unblocked** —
  `unfinished/feature-pcl-component-ctor-owner`: make `classes_lite.TReader`
  construct via the metaclass virtual ctor and REVERT the 4 constructor-skip
  stopgaps (grep `bug-metaclass-new-getclass-vmt` / `done/bug-lfm-streaming-skips-
  constructors`: TPaintBox Canvas guard in CreateHandle, TListBox/TComboBox
  grow-on-demand, the CreateInstance contract note). **Do the streamer adoption
  first** — it's the foundation for instantiating dropped/streamed components via
  their real ctors, and clears tech debt.

### M5 — `feature-eliah-selection-link` (backlog)
One shared **bidirectional selection model** (render-agnostic, in `garin`,
bochan-tested): designer↔editor.
- Designer → editor: select a widget → scroll/highlight its creation + event code.
- Editor → designer: caret on a component identifier → select it in the designer.
- Command surface: actions take the selection (e.g. "wire OnClick" → handler stub
  + assignment). AI tooling is just another command source + a console pane — no
  layout/mode special-casing.

## Suggested order
1. **Streamer adoption** (`feature-pcl-component-ctor-owner`) — unblocked by v46;
   reverts stopgaps; foundation for real construction. ~contained.
2. **M4 palette** — builds on the registry + real construction.
3. **M5 selection-link** — mostly independent; can interleave.

## Start
Read `devdocs/progress/BOARD.md`, the three tickets above, and
`done/feature-eliah-shell.md`. Confirm build + `--smoke` + a `gui_shot.sh`
screenshot are green BEFORE changing anything. Memory index at
`/home/rene/.claude/projects/-home-rene-frank2/memory/MEMORY.md`.
