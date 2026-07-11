---
prio: 45  # auto
---

# feature: Eliah tabbed component bar (Lazarus-style, with icons)

- **Type:** feature (Track B)
- **Status:** done
- **Track:** B
- **Parent:** feature-eliah-ide
- **Opened:** 2026-06-24

## Goal

Replace (or augment) the flat palette combo with a **tabbed component bar** along
the toolbar — Lazarus/Delphi style: tabs (Standard / Additional / Non-visual / …)
each holding a row of **icon buttons**, one per registered component. Click an
icon to arm Place for that component.

## Why

The combo is registry-driven but cramped and text-only. A tabbed icon bar is the
expected RAD-IDE affordance and scales better as more components register.

## Scope

- A tab strip + per-tab icon row, driven by the same registry enumeration the
  combo uses (`EnumDescendants('TComponent')` + `CompPlaceKind`). Grouping by the
  category the combo already computes (visual vs non-visual; later finer groups).
- Icons: needs small per-component glyphs. Options — a tiny built-in icon font /
  drawn glyphs (TPaintBox per cell), or bundled PNGs in `apps/ide/eliah/icons/`.
  Start with drawn placeholders (first letter / shape) so it works before art.
- Clicking an icon sets the active palette selection + arms Place (sticky), same
  path the combo + OnDesignMouseDown already use — no new placement logic.
- Keep it data-driven: a newly `RegisterClass`'d component appears as a new icon
  with no IDE edit, exactly like the combo today.

## Dependencies / notes

- PCL gap: there is no tab control yet (`TPageControl`/`TTabSheet`) and no toolbar
  icon-button container. Either add a minimal `TTabBar` to PCL (TWidgetSet
  virtuals are safe again — see `done/bug-widgetset-virtual-arg-corruption`) or
  build it directly via `gtk3_c` (gtk notebook + button box), like graphics.pas.
- Concept art may exist under `concept-art/` (untracked) — check before drawing.
- Could live in eliah.lfm once a tab/iconbar widget exists (dogfood-friendly).

## Acceptance

A tabbed icon bar replaces/augments the palette combo; clicking an icon arms Place
for that component; tabs group visual vs non-visual; adding a registered component
surfaces a new icon with no IDE edit. gui_suite green; screenshot of the bar.

## Log
- 2026-06-24 — filed from GUI-testing feedback (Lazarus-style component bar).

## Log

- 2026-07-12 (opus-night) — **landed.**
  - PCL: `TTabBar` in extctrls (GtkNotebook of horizontal button rows, built
    directly on gtk3_c like graphics.pas; gtk3_c.h gained the 4 notebook
    decls). `AddTab(caption)`, `AddButton(tab, caption, onClick)` (real
    TButtons → normal click trampoline), `TabCount`/`ActiveTab`/
    `SetActiveTab`. New `test/gui/test_pcl_tabbar.pas` in the gui suite.
  - Eliah: `CompBar: TTabBar` under the button row (TOOLBAR_H 40 → 104),
    tabs Standard / Non-visual, driven by the SAME registry enumeration as
    the combo (BarRows maps buttons to palette rows); clicking a component
    button selects its palette row and arms Place (sticky). Combo kept
    (augment, not replace). Captions are 3-char placeholders until glyph art
    exists (the ticket's intended bootstrap). Smoke asserts: 2 tabs, buttons
    present, a real gtk click selects the row + arms Place.
  - **Compiler bug found + filed:** [[bug-tobject-param-truncated-32bit]]
    (Track A, prio 60) — a `Sender: TObject` parameter arrives 32-bit
    truncated in methods (and is rejected outright in plain routines); every
    PCL handler that reads Sender's value is affected. Eliah's handler is
    typed `Sender: TButton` as the workaround (commented).
  - `make gui-test` fully green (incl. the 3 real-window xvfb cases).
  Remaining (cosmetic follow-up, not blocking): real per-component glyphs to
  replace the caption placeholders; finer tab groups beyond visual/non-visual.
- 2026-07-12 — resolved, commit d20d35dc.
