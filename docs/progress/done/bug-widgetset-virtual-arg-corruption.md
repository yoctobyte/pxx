# bug: new virtual method on TWidgetSet miscompiles its object argument

- **Type:** bug
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-23

## Summary

Adding a new `virtual` method to `lib/pcl/uwidgetset.TWidgetSet` (overridden in
`gtk3widgets.TGtk3WidgetSet`, dispatched through the base-typed global
`WidgetSet: TWidgetSet`) miscompiles the method's **first object argument**: the
callee receives a garbage pointer in place of the object, while a trailing
`Integer` argument arrives correct. Dereferencing the bad pointer segfaults.

Discovered building the `TPaned` widget (Track B, draggable splitters). Three new
methods were added — `CreatePaned(AComp; AVertical)`, `SetPanedPosition(AComp;
APos)`, `GetPanedPosition(AComp)`. Observations:

- `WidgetSet.SetPanedPosition(P, 150)` ran the right method body (confirmed via a
  debug `writeln`) but `TControl(APaned).Handle` read `0x41E654`-ish (a
  code-segment address), not the real gtk handle. `APos` was the correct `150`.
- The identical call inlined as `gtk_paned_set_position(P.Handle, 150)` (direct,
  no widgetset) worked.
- `CreatePaned` "worked" only because its body never dereferences `APaned` (it
  uses only the `AVertical` flag).
- Existing widgetset methods with the same `(TComponent, Integer…)` shape
  (`SetBounds`, slot 16) work fine — so it is not simply "object arg through a
  base-typed global virtual."

## Not yet minimally isolated

A single-unit class with 42 `(TThing, Integer)` virtuals does **not** reproduce
(args intact). A 2-unit attempt reproduced a crash but turned out to be a
*different* issue — a unit `initialization` section assigning the global was not
running, leaving it nil; an explicit init call fixed that case. So the precise
trigger (cross-unit + ~42-slot vtable + the managed-`string`-returning methods
that sit mid-vtable, e.g. `GetMemoText`/`SelectFolder`, + override dispatch)
is not yet reduced to a clean repro. The PCL-context failure is 100% reproducible
(see git history of this change / the `TPaned` work).

## Workaround in tree (undo when fixed)

`lib/pcl/extctrls.pas` `TPaned` talks to gtk **directly** via `gtk3_c`
(`gtk_paned_new` / `gtk_paned_set_position` / `gtk_paned_get_position`) instead of
routing through `TWidgetSet` methods — the same direct-gtk style `graphics.pas`
already uses, so it is idiomatic here, not a hack. The child packing
(`gtk_paned_pack1/2`) lives in the **existing** `TGtk3WidgetSet.SetParent`
(`TPaned` branch), which is an established virtual slot and works.

Undo once this ticket lands: move paned create/position into proper `TWidgetSet`
virtuals (`CreatePaned` / `SetPanedPosition` / `GetPanedPosition`) and drop the
`gtk3_c` calls from `extctrls`. Grep marker: `bug-widgetset-virtual-arg-corruption`.

## Log
- 2026-06-23 — filed from Track B (TPaned / draggable splitters). Workaround:
  TPaned calls gtk directly.
