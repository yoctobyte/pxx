---
prio: 45  # auto
---

# feature: Eliah tabbed component bar (Lazarus-style, with icons)

- **Type:** feature (Track B)
- **Status:** backlog
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
