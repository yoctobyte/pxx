# feature: Eliah component palette — registry-driven (visual + non-visual tray)

- **Type:** feature (Track B)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-shell
- **Opened:** 2026-06-23

## Goal

Drive the designer palette from a **component registry**, not a hardcoded list.
A component is any registered `TComponent` with published RTTI — visual widgets
*and* non-visual libraries wrapped as components are the same thing.

## Why

"Components are either GUI elements or libraries wrapped as components." Wrapping
a library (JSON client, data source, timer) as a published `TComponent` +
`RegisterClass` should make it appear in the palette with zero IDE special-casing.
The `Create(AOwner)` virtual-ctor model (just landed) is the foundation.

## Scope

- **Registry surface**: enumerate `RegisterClass`'d components (reuse the
  `GetClass`/RTTI registry the streamer already uses). Each entry: class name,
  visual/non-visual flag, (optional) icon/caption.
- **Palette pane**: lists registered components, grouped (Standard / Additional /
  custom). Replaces the current fixed palette combo.
- **Drop behaviour**:
  - Visual → instantiated onto the form surface at the drop point (today's path).
  - **Non-visual → a tray strip along the form bottom** (Delphi-style icon tray);
    selectable, editable in the inspector, but not positioned on the canvas.
- Inspector edits visual and non-visual components identically (published RTTI).

## Dependency note

Instantiating a dropped component via its real virtual ctor wants
`urgent/bug-metaclass-new-getclass-vmt` fixed (metaclass `Create(AOwner)` with a
canonical VMT). Until then, the designer can keep its current doc-model
instantiation for visual widgets; the **registry-driven palette + non-visual
tray** can land independently of that.

## Acceptance

The palette is populated from the registry (adding a `RegisterClass`'d component
makes it appear, no IDE edit); dropping a visual component places it on the form;
dropping a non-visual one adds a tray icon; the inspector edits both via RTTI.
`gui_suite` + garin green; screenshot of palette + a non-visual tray item.

## Log
- 2026-06-23 — filed (milestone 4 of feature-eliah-shell).

## Progress 2026-06-24 — registry surface + registry-driven palette DONE

- **Registry surface** (garin/registry.pas, render-agnostic, bochan-tested 10
  asserts): `EnumDescendants(ancestorName, includeSelf)` walks the
  compiler-emitted RTTI registry (__rttireg); `ClassDescendsFrom` is the
  ancestor-chain test. The face supplies the PCL ancestor names — core stays
  generic. Foundation commit ee2a7de.
- **Palette pane**: the designer combo is now populated from the registry
  (visual = descends from TControl, filtered to docmodel-placeable kinds via
  CompPlaceKind). RegisterClass'ing a new placeable widget surfaces it with no
  IDE edit. Commit fceb968.
- Registry in eliah carries 17 components: 7 placeable visual (Button/Label/Edit/
  Memo/ListBox/CheckBox/Panel) + bases + non-visual (TTimer, TMenu*, TMenuItem).

### Remaining (keeps this ticket open)
- **Non-visual tray** (the distinctive bullet): drop a non-visual component
  (TTimer, a wrapped library) -> a Delphi-style icon tray along the form bottom;
  selectable + inspector-editable but not on the canvas. Needs docmodel support
  for a non-visual node (no X/Y/canvas rect) + designer tray-strip rendering +
  place routing (visual->canvas, non-visual->tray). Registry already classifies
  non-visual (TComponent but not TControl), so the data is ready.
- **Grouping** (Standard/Additional) in the palette — minor; defer with the tray.
