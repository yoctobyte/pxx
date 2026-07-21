---
summary: "PCL: seal the TWidgetSet seam — route extctrls/dialogs/glarea through the widgetset so ZERO raw gtk_ lives outside gtk3widgets.pas (enabler for any 2nd backend)"
type: feature
prio: 25
---

# PCL — seal the leaky TWidgetSet seam

- **Type:** feature / refactor (**Track B** — `lib/pcl`). Gate = `make lib-test` +
  the `test/gui/*` suite green; behaviour byte-unchanged on GTK.
- **Status:** backlog. Child of [[feature-pcl-cross-platform-gui]]. **The enabler** —
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
