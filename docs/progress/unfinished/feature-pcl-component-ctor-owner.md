# feature: PCL components adopt the `Create(AOwner)` virtual-constructor shape

- **Type:** feature (Track B — lib/pcl component model)
- **Status:** backlog — UNBLOCKED 2026-06-23 (language half landed)
- **Opened:** 2026-06-23

> **Unblocked 2026-06-23:** the compiler half is DONE
> (`done/feature-metaclass-construct-dispatch`, pinned v44). `classRefVar.Create(args)`
> dispatches through the dynamic VMT, parametrised virtual ctors work, and the
> `TBaseClass(GetClass(name)).Create(AOwner)` bridge is verified. PCL can now adopt
> the `Create(AOwner); virtual;` shape and have the streamer construct via metaclass.

## Goal

Shape PCL's component/control classes like FPC's so the same source could compile
under both and so the streamer constructs them through a metaclass:

- a **virtual** `constructor Create(AOwner: TComponent); virtual;` on the
  component base (currently PCL uses a parameterless `constructor Create;`),
- a minimal Owner/Components linkage so streamed objects have an owner.

This is the library half of `urgent/feature-metaclass-construct-dispatch` (the
language half). They meet at "streaming constructs a component with an owner".

## Ownership stance (deliberate)

FPC's `TComponent` auto-frees its owned children. We support the **shape** for
compatibility but do NOT impose the religion:

- **`Owner = nil` is first-class.** In-app usage may pass `nil` and just set
  `Parent` — exactly as much FPC code already does. Manual free stays valid.
- Keep the Owner/Components list minimal (enough for streaming + FPC source to
  compile + optional cascade-free), not a mandatory lifecycle.

Rationale: the owner system solves some problems and creates others (nil-owner +
parent-only is a common, cleaner app pattern). Compatibility ≠ enforcement.

## Scope

- `TComponent.Create(AOwner: TComponent); virtual;` + `Owner`/`Components`
  (insert on create, optional cascade free on destroy).
- Migrate `TControl`/widgets to call `inherited Create(AOwner)` and stop relying
  on the parameterless form (keep a parameterless convenience if useful).
- Once `metaclass-construct-dispatch` lands: the streamer calls
  `classRef.Create(owner)`; REVERT the constructor-skip stopgaps
  (`done/bug-lfm-streaming-skips-constructors`) — Canvas back in TPaintBox.Create,
  arrays back in TListBox/TComboBox.Create, drop the CreateInstance contract note.

## Acceptance

A streamed widget tree is constructed via `Create(AOwner)` (Owner may be nil),
widgets keep their natural constructors (no CreateHandle/lazy stopgaps), Eliah +
gui_suite green. App code that passes `nil` owner + sets `Parent` works unchanged.

## Note

Blocked-by `urgent/feature-metaclass-construct-dispatch` for the streaming path,
but the `Create(AOwner)` migration itself can proceed independently.
