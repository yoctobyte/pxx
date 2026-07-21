---
summary: "DECIDE: NilPy `import tk` — thin tk-face over the common PCL core (A) vs keep the real Tcl/Tk embed (B)"
type: decide
prio: 30
---

# DECIDE — NilPy GUI: tk-face over PCL, or real Tcl/Tk embed?

- **Type:** Track U (decision). No files, no gate — a fork for the user to settle.
- **Status:** backlog. Blocks nothing yet; **resolve when NilPy GUI is actually
  scheduled.** Filed pre-answered so it's a confirm, not a fresh debate.
- **Opened:** 2026-07-21, GUI-scope session. Parent: [[feature-pcl-cross-platform-gui]].

## The fork

NilPy `import tk` must yield a tk-compatible API that "just works." Two ways:

- **(A) thin tk-shaped FACE over the common PCL core** *(recommended)*. tk becomes one
  more *face* in one-core-N-faces; it rides the same `TWidgetSet` seam Pascal uses, so it
  inherits the gtk default + [[feature-pcl-win32-widgetset]] + any future qt **free**,
  with **zero extra deps**. Obeys the lowest-common-denominator + zero-dep doctrine.
  Cost: reimplement the tk-API surface NilPy uses as a veneer, and migrate the NilPy IDE
  (Track E) off the real-Tk embed.
- **(B) keep the real Tcl/Tk embed** (`lib/pcl/tk.pas`, string-eval into libtcl/libtk).
  Works today, mature. But it's a **fat external dependency** and a *separate* toolkit:
  it does NOT ride the PCL core, won't inherit win32/qt, and reopens the Windows
  DLL-swarm problem (libtcl/libtk .dll bundle) that the zero-dep rule exists to avoid.

## Trade-off

| | (A) face over PCL | (B) real Tcl/Tk embed |
|---|---|---|
| deps | zero (rides PCL) | fat (libtcl/libtk) |
| inherits win32/qt | yes, free | no, separate stack |
| lowest-denominator | obeys | violates |
| works today | no (build it) | yes |
| Windows | clean (win32 widgetset) | DLL-swarm again |

## Recommendation

**(A).** It's the only reading consistent with everything else decided
(lowest-common-denominator, zero-dep, one-core-N-faces, gtk-golden). Keep the `tk.pas`
real embed as the **interim IDE vehicle** until the tk-face lands, then retire it.

## When resolved
If (A): re-file as a Track B `feature-pcl-tk-face` (veneer over PCL) + a Track E
migration note for the NilPy IDE. If (B): document the dep + a Windows carve-out, and
drop tk from the lowest-denominator guarantee.
