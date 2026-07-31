---
summary: "PCL: seal the TWidgetSet seam — route extctrls/dialogs/glarea through the widgetset so ZERO raw gtk_ lives outside gtk3widgets.pas (enabler for any 2nd backend)"
type: feature
prio: 25
---

# PCL — seal the leaky TWidgetSet seam

- **Type:** feature / refactor (**Track B** — `lib/pcl`). Gate = `make lib-test` +
  the `test/gui/*` suite green; behaviour byte-unchanged on GTK.
- **Status:** done
  no second widgetset ([[feature-pcl-win32-widgetset]], Qt) can exist until this lands.
- **Owner:** —
- **Opened:** 2026-07-21, from the GUI scout.

## Problem

PCL already has a real backend seam — abstract `TWidgetSet` (~40 virtuals)
`lib/pcl/uwidgetset.pas:9`, global `WidgetSet` `:62`, concrete `TGtk3WidgetSet`
`lib/pcl/gtk3widgets.pas:9`. Core controls/forms dispatch through it cleanly. **But
three units call GTK raw, bypassing the seam:**

- `lib/pcl/extctrls.pas` — **24** direct `gtk_` calls in TPaned/TBox/TTabBar/TPanel/
  TPaintBox/TTimer (`uses gtk3_c`), e.g. `gtk_paned_new` `:153`, `gtk_notebook_new` `:332`.
- `lib/pcl/dialogs.pas` — **7** (`ShowMessage` → `gtk_message_dialog_new`/`gtk_dialog_run`
  `:32,35`).
- `lib/pcl/glarea.pas` — **5** (`TGLArea`).

While ~36 `gtk_` calls live outside `gtk3widgets.pas`, a Win32 or Qt widgetset can only
implement *part* of PCL — the leaked widgets would silently stay GTK (i.e. not compile /
not exist off-GTK). Sealing is the precondition for the whole cross-platform story.

## Shape

- For each leaked widget, add the needed operations as **virtual methods on
  `TWidgetSet`** (`uwidgetset.pas`) and move the GTK bodies into `TGtk3WidgetSet`
  (`gtk3widgets.pas`), matching how stdctrls/forms already do it.
- The widget classes in `extctrls`/`dialogs`/`glarea` then call `WidgetSet.Xxx(...)`,
  drop `uses gtk3_c`, and hold only an opaque `Handle`.
- Where a widget is inherently backend-specific (`TGLArea` = GL context surface), the
  seam method may return a capability/nil off-GTK rather than force every backend to
  implement GL — document that as an allowed sparse point, not a leak.

## Acceptance

- **Grep gate:** `grep -rn 'gtk_' lib/pcl` returns hits **only** in `gtk3widgets.pas`
  (and the `gtk3_c.h`/`gtk3.pas` import decls). Zero `gtk_` in extctrls/dialogs/glarea.
- No `uses gtk3_c` / `uses gtk3` outside the gtk3 widgetset unit + interfaces glue.
- `make lib-test` green; every `test/gui/test_pcl_*` passes unchanged (click, drawing,
  menus, paned, showmessage, tabbar, widgets, window, lfm, stream_paned).
- The GUI demos (`solitaire_gui`, `raytracer_gui`, `mandelbrot_gui`, `life`) build and
  run identically under gtk3 — this is a pure refactor, zero visible change.

## Note
Pure Track B. No compiler change. Land in one pass; it's mechanical (move bodies, add
virtuals) and the existing gtk3 impl is the reference for every method signature.

## RESOLVED 2026-07-31 — the seam is sealed

`grep -rn 'gtk_' lib/pcl/*.pas` now returns hits ONLY in `gtk3widgets.pas`,
`gtk3.pas` (the import declarations) and the new `gtk3gl.pas`. Zero in
`extctrls`, `dialogs` and `glarea`; `uses gtk3_c` / `uses gtk3` are gone from
all three.

### What moved

- **extctrls (24 calls).** TPaned, TBox and TTabBar now hold an opaque `Handle`
  and call `WidgetSet.CreatePaned/PanedSetPosition/PanedGetPosition/PanedChild`,
  `CreateBox/BoxPack`, `CreateNotebook/NotebookAddPage/NotebookGetPage/
  NotebookSetPage`, plus the handle-addressed `ShowHandle/HideHandle/
  HandleWidth/HandleHeight`. Those four exist because a paned's child and a
  notebook's page box are widgets PCL never wrapped in a control, so the
  TComponent-keyed calls could not reach them.
  `NotebookAddPage` takes the caption as a STRING and builds the label itself —
  making the caller build a label widget would have leaked the toolkit again.
- **dialogs (7 calls).** `ShowMessage` / `DismissActiveDialog` are two lines over
  `WidgetSet.MessageBox` / `DismissMessageBox`. The dialog handle moved into the
  widgetset, because it is the widgetset's; the `ActiveDialog` variable this unit
  exported is gone, and both callers only ever used `DismissActiveDialog`.

### The GL sparse point, and why it is a separate unit

The ticket allows TGLArea to be a sparse point. It turned out to need one for a
**measured** reason, not a stylistic one: the GL entry points come from a
separate shared library, so putting them on `TGtk3WidgetSet` gave every PCL
binary a `DT_NEEDED` on `libgl_c.so` — and the entire GUI suite then failed to
start with `libgl_c.so: cannot open shared object file`. Only a program that
actually uses TGLArea should pay that.

So GL lives on its own object: `TGLBackend` in `uwidgetset.pas` (nil until
installed), implemented by `TGtk3GLBackend` in the new `lib/pcl/gtk3gl.pas`,
which `glarea.pas` uses purely to have a backend installed — it calls nothing
there by name, only `GLBackend.*`. A widgetset with no GL ships no backend and
TGLArea reports that honestly instead of forcing every backend to implement a GL
context.

### One comment that was load-bearing and is now wrong

`TPaned.CreateHandle` carried: *"Talk to gtk directly here rather than through a
WidgetSet method: adding new virtual methods to TWidgetSet currently miscompiles
their object argument."* That bug (`bug-widgetset-virtual-arg-corruption`) is
resolved, so the avoidance it justified is retired — which is the whole reason
this ticket could land as a mechanical move. The comment is replaced with one
that says so.

### Gate

- `tools/gui_suite.sh`: every `test_pcl_*` OK, plus `solitaire_gui` (smoke, real
  window and real-window-size), `life` real window. Byte-unchanged behaviour on
  GTK — this is a pure refactor.
- `tools/gate.sh lib` GREEN.

### The one red, pre-existing

`eliah_ide -- compile` fails, identically before and after this change (verified
against a stashed tree): `plist[j]^.Kind` hits a compiler bug where only the
FIRST field of a record reached through an array-of-pointer is resolvable. Filed
as [[bug-pascal-array-of-pointer-deref-loses-the-record-type]] (Track A). Note
the suite then runs the stale eliah binary and prints
`OK eliah_ide (real window ...)` two lines below the failure — that reporting gap
hides a red and is worth a Track T fix.

## Log
- 2026-07-31 — resolved, commit baecce983.
