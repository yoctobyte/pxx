---
summary: "UMBRELLA: cross-platform GUI — copy the LCL widgetset model; PCL = TComponent tree behind a TWidgetSet seam; compile-time widgetset select; sparse widgetset×OS matrix, hard-fail the rest"
type: feature
prio: 30
blocked-by: [feature-pcl-seam-seal, feature-pcl-widgetset-select, feature-pcl-win32-widgetset]
---

# UMBRELLA — cross-platform GUI: the LCL widgetset model, done sparsely

- **Type:** feature / umbrella (**Track B** — `lib/pcl`, built with `$(PXX_STABLE)`).
  Gate = `make lib-test` / `demos` green on Linux. One child (win32) additionally
  depends on Track A's Windows PE work — noted there, not here.
- **Status:** backlog (umbrella; tracks its children).
- **Owner:** —
- **Opened:** 2026-07-21, GUI-scope session. Doctrine below; ground-truth scout of
  today's `lib/pcl` inline.

## North star — don't reinvent a round wheel

FPC/Lazarus already solved cross-platform GUI **properly**: an interface layer
(`LCL` = forms/controls the app writes) sitting on a **widgetset** seam (`TWS*`),
with the concrete backend (gtk2/gtk3/qt/win32/cocoa) **selected at compile time**
(`-ws`). One binary, one widgetset baked in. That's the design we copy — the *cut
line*, not the 20-year surface.

The Borland `TComponent` model underneath (owner/owned + parent/child as **two
separate axes**, `FreeNotification`, published-property streaming) is the crown jewel;
it makes ~200 components cheap because they derive from ~5 bases. **Copy the hierarchy
whole; constrain the backends.** Cost is components × *widgetsets*, so we limit the
widgetset axis, not the component axis.

## What we accept

**Windows is a target — like it or not, users are there.** GUI on Windows is a real
goal, not a someday. It rides the OS-portability umbrella
[[feature-port-multi-os-abstraction]] (PE writer + MS x64 ABI) for the ability to emit
a Windows binary at all; this umbrella owns the *widget* half on top.

## Ground truth — what `lib/pcl` IS today (scout 2026-07-21)

Verdict **a-minus: real LCL-shaped lib WITH a backend seam, but the seam leaks.**

- **Seam exists.** Abstract `TWidgetSet` (~40 virtuals) `lib/pcl/uwidgetset.pas:9`,
  global `var WidgetSet` `:62`. Core controls/forms dispatch through it
  (`controls.pas`, `forms.pas`). One concrete impl: `TGtk3WidgetSet`
  `lib/pcl/gtk3widgets.pas:9` — the ONLY place `gtk_*` lives for the core.
- **TComponent model present + real.** `TComponent` `lib/rtl/classes_lite.pas:38`
  (Owner + `FChildren[]`), `TControl(TComponent)` `controls.pas:9`,
  `TWinControl(TControl)` `controls.pas:60`, `TForm` `forms.pas:9`, `TApplication`
  `forms.pas:23`, stdctrls leaves `stdctrls.pas:10..87`.
- **Streaming works + is tested.** DFM-subset `TReader`/"TPF0" in `classes_lite.pas`,
  LFM→TPF0 `lib/rtl/lfm.pas:33`; load path `TApplication.CreateForm` → RTTI. Tests:
  `test/gui/test_pcl_lfm.pas`, `test_pcl_stream_paned.pas`.
- **GTK-only.** No Qt/Win32/cocoa anywhere; `TGtk3WidgetSet` is the sole subclass.

### Three facts that shape the children
1. **The seam LEAKS.** `extctrls.pas` (24 raw `gtk_`, e.g. `gtk_paned_new` `:153`),
   `dialogs.pas` (7), `glarea.pas` (5) call GTK **directly**, bypassing `TWidgetSet`.
   → a second widgetset is **impossible** until sealed. See [[feature-pcl-seam-seal]].
2. **Selection is hardwired.** `interfaces.pas:6` does `uses gtk3widgets` unconditionally
   — no `--widgetset`, no matrix, no hard-fail. See [[feature-pcl-widgetset-select]].
3. **tk today is NOT a PCL face** — `lib/pcl/tk.pas` is a separate Tcl/Tk string-eval
   embed (fat external libtcl/libtk dep, used by the NilPy IDE, Track E), explicitly
   "NOT a widget layer." The direction (below) is a thin tk **face over the common PCL
   core**, keeping the real-Tk embed only as interim IDE vehicle. Confirm before ripping
   it → Track U `decide-nilpy-gui-tk-vs-pcl`.

## Settled design (2026-07-21, user) — the lowest-common-denominator rule

The load-bearing principle, and the real answer to "what is the right level":

> **The neutral core exposes only what ALL backends share — the intersection, not any
> toolkit's superset.** GTK's extras, Qt's extras, Win32's extras stay *below* the seam.
> `qt != gtk`, so the API is their common subset. This is what keeps the seam thin and
> every backend cheap; it's the concrete meaning of "abstract at the right level."

Concrete calls (each a deliberate scope cap, not a gap to fill later):

- **Pascal GUI default = GTK — the golden/reference backend.** Pascal settles here; no
  per-app widgetset choice by default. Everything else is measured against gtk behaviour.
- **NilPy `import tk` → a tk-compat layer that "just works," riding the common core.**
  No more, no less. **Recommended shape (A):** a thin tk-shaped *face* over PCL (so it
  inherits gtk-default + win32 + any future qt for free, zero extra deps) — NOT a second
  real-toolkit embed. The existing `tk.pas` real Tcl/Tk embed is the interim vehicle;
  reconcile via `decide-nilpy-gui-tk-vs-pcl` before removing it. (Rejected shape (B):
  keep embedding real Tcl/Tk — fat dep, a *separate* toolkit that would NOT ride the core
  and breaks lowest-denominator + zero-dep, esp. the Windows DLL-swarm rule.)
- **Windows = the win32 compat widgetset** ([[feature-pcl-win32-widgetset]]).
- **Qt = someday, low** — "pull in the qt lib, call it a day." Trivial *if* the seam is
  clean; **no ticket until a real consumer asks.** The seam is shaped for it, not filled.
- **Everything else (other toolkits/OSes) = a plain to-do — below rainy-day.** If the
  abstraction is right, each is a `TWidgetSet` subclass + a matrix row, i.e. trivial. So
  none is worth a ticket speculatively.

## Children (the plan)

1. **[[feature-pcl-seam-seal]]** (Track B) — route `extctrls`/`dialogs`/`glarea`
   through `TWidgetSet`; zero raw `gtk_` outside `gtk3widgets.pas`. The **enabler** —
   nothing else lands first. GTK-only, no behaviour change, fully testable today.
2. **[[feature-pcl-widgetset-select]]** (Track B, small CLI touch) — `--widgetset=` +
   compile-time bake + the **sparse widgetset×OS matrix as a hard compile error** for
   unshipped/untested cells. With only gtk3 today it's a 1-cell matrix; it exists so
   adding win32 is a table entry, not a rewire.
3. **[[feature-pcl-win32-widgetset]]** (Track B; blocked-by #1 **and** the Track A
   Windows PE work) — a second `TWidgetSet` subclass, native user32/gdi32, zero-dep.
   **Best-effort, UN-GATED** (no Windows box, Wine-smoke only).

## The matrix (start sparse, grow by table entry)

| widgetset | linux | windows | notes |
|---|---|---|---|
| **gtk3** | ✅ ship+test | ❌ 30-40 MB DLL swarm — refuse | today's only working cell |
| **win32** | ❌ n/a | ⚠️ best-effort / Wine-smoke | child #3 |
| **qt** | 🔜 future, no ticket | ❌ not delivered | no consumer yet — don't pre-build |

Every ❌/🔜 = a **compile-time refusal with a reason**, never a silent broken build.

## Deliberate limits (say no in the ticket, not in a bug report later)
- **One core, N faces, M backends** — not one GUI stack per frontend. tk/NilPy is a
  *face* question (open decision), never a parallel backend.
- **Qt: no ticket until a second consumer exists** — abstraction earns its keep at the
  2nd backend, not the 1st. The seam is *shaped* for it (that's #1); it is not *filled*.
- **GTK-on-Windows: refused** — the DLL swarm breaks the single-binary identity. Windows
  GUI = native win32 only.
- **Windows GUI parity: not guaranteed, not gated** — Wine is the only oracle; real-HW
  bugs get filed when a Windows box appears, not pre-solved.

## Known LCL-fidelity gaps (backlog, low prio — note now, fix when they bite)
- `TWinControl` is an empty stub (`controls.pas:60`) — no distinct windowed semantics.
- **Display tree == ownership tree** — `TControl.SetParent` `controls.pas:226` reuses
  the TComponent `FChildren[]`. VCL keeps Parent/Owner as *two* axes on purpose; merging
  them will bite (re-parent without re-own). A fidelity fix, not urgent.
- **`FChildren` fixed at 64** (`classes_lite.pas:80`) — a hard cap that WILL bite a real
  form. Small bug ticket when a demo hits it.

## Acceptance (umbrella)
- #1 + #2 + #3 resolved and green.
- Linux: `--widgetset=gtk3` builds every PCL demo, `make lib-test`/`demos` green,
  **zero `gtk_` outside `gtk3widgets.pas`**.
- Windows: `--widgetset=win32 --target=x86_64-windows` opens a native window under Wine
  (best-effort smoke via [[feature-t-windows-wine-harness]]).
- Unsupported matrix cells (`--widgetset=qt --target=windows`, `gtk3`+windows) **fail at
  compile time with a clear reason**, never silently.
