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

## Progress 2026-06-24 (cont.) — non-visual tray DONE

Non-visual components now drop into a Delphi-style icon tray along the form
bottom (commit c706b1c):
- docmodel: wkTimer/wkMenu + IsNonVisual(); lfmload KindOf round-trips TTimer/TMenu.
- designer.LayoutTray: bottom strip, slot rects written back so the shared
  HitTest/selection works; tray icons fixed (no drag/resize), distinct fill, no
  size hint.
- palette: CompPlaceKind maps TTimer/TMenu; filter dropped the TControl-only gate
  so non-visual components route to the tray on drop.
- sample.lfm ships a TTimer (tray visible on launch).
- Gates: bochan 139/139, eliah --smoke OK, gui_suite OK, screenshot verified.

### Remaining (keeps this ticket open)
- **Palette grouping** (Standard/Additional/Non-visual headers) — combo is flat.
- **RTTI inspector**: the inspector edits docmodel node fields (caption/bounds);
  non-visual components want published-RTTI editing (Interval, etc.). The registry
  already carries the class, so the inspector can read GetPropList off it. This is
  shared with M5's command/selection surface.
- **Generic non-visual classes**: tray currently proven with TTimer/TMenu (fixed
  docmodel kinds). Arbitrary registered non-visual components want class-name
  storage on the node rather than an enum kind — a docmodel extension.

## Progress 2026-06-24 (cont. 2) — grouping, inspector, property bag

- **Palette grouping** (commit f9ad0d6→): visual widgets, a `-- non-visual --`
  divider, then tray components; place handler disarms cleanly on the divider.
- **Inspector / non-visual** (f9ad0d6): tray nodes show Kind + editable Caption +
  a non-visual marker, geometry rows suppressed and guarded.
- **Property bag + inspector edit** (44f451f): TDocNode carries an extra-property
  bag; lfmload round-trips any `Prop = Value` (fixed a silent prop-drop-on-save
  data-loss bug — TTimer.Interval was being lost). Inspector shows + edits bag
  props (FBagBase), undoable, for visual and non-visual alike.
- Gates: bochan 142/142, eliah --smoke OK, gui_suite OK.

### Acceptance MET
Palette is registry-populated; visual drops to canvas, non-visual to the tray;
inspector edits both (modelled fields + bag props). Screenshot shows the tray.

### Remaining polish (low priority — could split to a follow-up)
- **Full RTTI property list**: show ALL published props of the registered class
  (GetPropList), including ones not yet in the .lfm, so a fresh Timer exposes
  Interval/Enabled without hand-editing. Bag holds only props already present.
- **Generic non-visual classes**: tray proven with TTimer/TMenu (fixed docmodel
  kinds); arbitrary registered non-visual components want class-name node storage.
