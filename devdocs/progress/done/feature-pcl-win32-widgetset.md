---
summary: "PCL: native Win32 widgetset — a 2nd TWidgetSet subclass over user32/gdi32, zero-dep (no GTK bundle). Best-effort, UN-GATED (no Windows box, Wine-smoke only)"
type: feature
track: M
prio: 25
blocked-by: [feature-pcl-seam-seal, feature-port-windows-pe]
---

# PCL — native Win32 widgetset (user32/gdi32, zero-dep, best-effort)

- **Type:** feature (**Track B** — `lib/pcl`, built with `$(PXX_STABLE)`).
- **Status:** done
  **Blocked-by two lanes:** [[feature-pcl-seam-seal]] (Track B — a total seam to
  implement against) **and** [[feature-port-windows-pe]] (Track A — a PE that boots +
  the IAT to import user32/gdi32/kernel32). Cannot start until both land.
- **Owner:** —
- **Opened:** 2026-07-21, GUI-scope session. (Supersedes the earlier
  `feature-port-windows-gui-pal` sketch, which predated the PCL scout — this is a
  `TWidgetSet` subclass, not a from-scratch layer.)

## What it is

A **second `TWidgetSet` subclass** — `TWin32WidgetSet` — alongside the existing
`TGtk3WidgetSet` (`lib/pcl/gtk3widgets.pas:9`), implementing the same ~40 virtuals
(`lib/pcl/uwidgetset.pas:9`) against **native Win32** instead of GTK. The whole PCL
component tree, streaming, and app code sit on top unchanged — that's the point of the
seam.

## Decision — native Win32, NOT GTK (recorded, do not re-litigate)

- **License is not the blocker** (GTK is LGPL; dynamic-linking a DLL doesn't copyleft).
- **The dependency swarm is** — "ship gtk3.dll" is really ~20-25 DLLs + a `share/` tree,
  ~30-40 MB, breaking pxx's single-self-contained-binary identity.
- **Native user32/gdi32 = 2 OS-provided DLLs**, always present, import-only, zero bundle,
  zero license. This is the zero-dep doctrine. GTK-on-Windows is refused
  ([[feature-pcl-widgetset-select]] hard-fails it).

## Shape

- Import user32/gdi32/kernel32 **exports via the PE IAT** (machinery from
  [[feature-port-windows-pe]]).
- `TWin32WidgetSet` maps the seam onto Win32: `RegisterClassW` + `CreateWindowExW` for
  widgets, a `GetMessage`/`TranslateMessage`/`DispatchMessage` pump driven by
  `TApplication.Run`, a `WndProc` routing `WM_*` → PCL's event dispatch
  (`OnClick`/`OnPaint`/…), `BeginPaint`/`GetDC` + gdi32 for the `TCanvas` paint path.
- **Single-threaded** — consistent with [[feature-port-windows-pe]] deferring
  threads/sync; the message loop is one thread, no palthread dependency.
- `TGLArea` may be a sparse/nil capability here (no WGL initially) — allowed per the
  seam-seal note, not a blocker.

## Explicitly NOT guaranteed / NOT gated

No Windows box exists — Wine is the only oracle and is not pixel-faithful. So:
- Correctness, styling, layout, DPI, font metrics, event-timing parity on **real
  Windows are NOT guaranteed and NOT tested.** Best-effort only.
- Real-hardware bugs get filed when a Windows box appears, not pre-solved.
- This ticket does **not** gate the GUI umbrella or the OS umbrella; console+stdio earns
  "runs on Windows," GUI bolts on.

## Delivered (2026-11-16)

- `lib/pcl/win32widgets.pas` (`TWin32WidgetSet`); `interfaces.pas` selects it by
  default for `--os=windows` (the guard is `PXX_OS_WINDOWS`; `--os=windows` does not
  define `WINDOWS`). No `-dWIDGETSET_WIN32` is needed.
- `graphics.pas` has a GDI path under `PXX_OS_WINDOWS`: TCanvas on an HDC, TBitmap
  as a top-down 32-bit DIB section (the same B,G,R,A bytes as cairo ARGB32).
- Covered: form, button, label, edit, check box, panel, memo, list box, combo box,
  paint box (double-buffered), menus with mnemonics/separators/enable, TTimer,
  MessageBox, open/save file dialogs (comdlg32), OnResize, mouse, and keys delivered
  as GDK keyvals so programs written against the GTK set need no change.
  `Application.Terminate` was added to forms.pas for programs that called
  `gtk_main_quit`.
- Not yet: TPaned, TBox, TToolBar, TTreeView, TNotebook, the folder chooser, GL areas,
  `DismissModal`.
- Imports: kernel32, user32, gdi32 and comdlg32 (the file dialogs), all of them
  shipped with every Windows and ReactOS.
- Tested: `make test-windows` builds `test/test_pcl_win32_widgets.pas` (all the
  controls; output compared with the GTK build) and `examples/solitaire_gui`
  (`--smoke`, `--gui-smoke`) and runs them under Wine with xvfb-run. Both also ran
  by hand on ReactOS 0.4.16 x64 (`tools/vm/reactos/rosinter.sh`): solitaire draws
  and plays, and the widget test prints the same lines.
- Found on ReactOS, not on Wine: an edit's EN_CHANGE arrives even when the text is
  set to the same value, and storing it back through `TEdit.Text` re-entered
  SetText until the stack ran out. SetText now skips unchanged text, the way
  `gtk_entry_set_text` does.

## Acceptance (intentionally minimal)

- A PCL app (`TForm` + a `TButton` + an `OnClick`, built `--widgetset=win32
  --target=x86_64-windows`) **opens and responds under Wine** (`xvfb`-wrapped headless
  smoke via [[feature-t-windows-wine-harness]]).
- Output contains **only** user32/gdi32/kernel32 imports — no GTK, no bundled DLLs.
- `grep -rn 'gtk_' ` in the win32 widgetset = zero (it's a parallel backend, shares no
  GTK code).
- Gate: `make lib-test` stays green on Linux; Windows GUI is Wine-smoke best-effort, NOT
  a byte-identical or pixel-parity gate.

## Log
- 2026-11-16 — resolved, commit c1b6577315.
