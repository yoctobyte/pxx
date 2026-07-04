# TComponent / TPersistent (FPC Classes owner-child surface)

- **Type:** feature (library — RTL Classes parity, Track B)
- **Status:** DONE 2026-07-04
- **Owner:** Track B

## What / why

FPC/FCL code (`custapp`, `eventlog`, and everything descending from
`TComponent`) needs `TComponent`/`TPersistent` in `Classes`. pxx had a reduced
`TComponent` only in `classes_lite` (the PCL streaming base), not in `classes`
where FPC's `uses Classes` resolves. Added the FPC-facing surface to
`lib/rtl/classes.pas`.

## Done (lib/rtl/classes.pas)

- `TPersistent = class(TObject)`: `Assign`/`AssignTo` (virtual; base
  `Assign(Source)` calls `Source.AssignTo(Self)`), `GetNamePath`.
- `TComponent = class(TPersistent)` owner-child model: virtual
  `Create(AOwner)` (registers with the owner), `Destroy` (frees owned
  components), `InsertComponent`/`RemoveComponent`, `FindComponent` (case-
  insensitive), `Notification` (virtual hook), + `Owner`, `Components[]`,
  `ComponentCount`, `Name`, `Tag` (NativeInt). `TComponentClass = class of
  TComponent`, `TOperation`.

Verified `test/test_tcomponent.pas` (ownership registration, indexed access,
FindComponent, owner-frees-children destructor counting, RemoveComponent detach)
= 9/9, on BOTH the fresh and the **pinned stable** compiler; wired into
`make lib-test`. Re-probing FPC `custapp`/`eventlog` now gets **past** the
`base type not found: TComponent` wall (advances to deeper, separate gaps).

## Pin-compatibility note

Initially `TComponent.Destroy` was `virtual`-introduce (no `inherited`) to build
on the v173 pin. After re-pinning to **v174** (which has this session's
implicit-`TObject.Destroy` override + `inherited Destroy` no-op), it was made
idiomatic: `destructor Destroy; override;` + `inherited Destroy`. Verified 9/9 on
the v174 pin.

## Landmines hit (filed)

- [[bug-forward-class-decl-with-later-base-loses-fields]] — the
  `TComponent = class; … TComponent = class(TPersistent)` idiom lost fields;
  worked around by dropping the forward decl.
- [[bug-downcast-inherited-property-wrong-offset]] — `TThing(ref).Tag` (downcast
  to an inherited property) read garbage; test reads via a base ref.
- `arr[i].Free` does not parse (known); temp-var workaround in `Destroy`.
- Bare `TFoo.Create(owner);` constructor-call-as-statement is rejected; assign
  the result to a temp.

## Follow-up

Grow toward more of FPC's `Classes` as consumers need (`TComponent` streaming
convergence with `classes_lite`, `TCollection`, `TComponent.Notification`
wiring on free). Separate tickets.
