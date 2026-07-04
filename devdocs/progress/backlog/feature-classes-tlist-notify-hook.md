# `TList.Notify` virtual hook + `TListNotification` — FPC Classes surface gap

- **Type:** feature (library — RTL Classes parity, Track B)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-04 (next FPC-compat wall after the compiler-side
  [[bug-tobject-destroy-not-virtual-override]] fix; see
  [[fpc-lcl-compile-probe]])
- **Track:** B — `lib/rtl/classes.pas` (RTL library body; file ownership per
  [[feedback_crtl_impl_is_track_b]]). NOT a compiler change — the virtual/
  override machinery it needs already works (the TObject.Destroy override fix
  proved it).

## Problem

FPC's `Classes.TList` exposes a protected virtual notification hook that
descendants override to react to element add/remove:

```pascal
{ FPC classesh.inc }
TListNotification = (lnAdded, lnExtracted, lnDeleted);
...
TList = class
  procedure Notify(Ptr: Pointer; Action: TListNotification); virtual;
  ...
```

`TList.Add`/`Delete`/`Remove`/`Clear`/`Extract` call `Notify` so a subclass can
hook the mutation. `contnrs.TObjectList(TList)` overrides it to free the removed
object:

```pascal
{ FPC contnrs.pp:78 }
TObjectList = class(TList)
  Protected
    Procedure Notify(Ptr: Pointer; Action: TListNotification); override;
```

pxx's `lib/rtl/classes.pas` `TList` (line ~62) implements
`Add/Delete/Insert/Clear/IndexOf/Remove/Get/Set` but has **no `Notify` method**
(and no `TListNotification` type). So compiling `uses contnrs` walls at the
override:

```
contnrs.pp:79: error: cannot override: no virtual method found in parent chain: Notify
```

(This is the wall the probe reached AFTER the TObject.Destroy override fix moved
`contnrs` past `:46`.)

## Fix (Track B, lib/rtl/classes.pas)

1. Add `TListNotification = (lnAdded, lnExtracted, lnDeleted);` (interface types).
2. Add `procedure Notify(Ptr: Pointer; Action: TListNotification); virtual;` to
   `TList` with a default empty body (base does nothing — the hook is for
   subclasses).
3. Call `Notify` from the mutators, matching FPC:
   - `Add` / `Insert` → `Notify(Item, lnAdded)` after storing.
   - `Delete` / `Remove` → `Notify(Item, lnDeleted)` before removing.
   - `Clear` → `Notify(Item, lnDeleted)` per element (FPC frees in reverse).
   - (`Extract` → `lnExtracted`, if/when Extract is added.)

Verified prerequisite: the compiler already supports a virtual method on a
library base being overridden by a user/RTL subclass and dispatched
polymorphically ([[bug-tobject-destroy-not-virtual-override]]), so this is purely
the library body.

## Acceptance

- `uses contnrs;` gets past the `Notify` override wall (next wall, if any, is a
  separate item).
- A smoke test: a `TList` subclass overriding `Notify` observes `lnAdded`/
  `lnDeleted` on `Add`/`Delete`; and a minimal `TObjectList` frees its owned
  objects on `Delete`/`Clear` when `OwnsObjects` is true.
- Builds with `$(PXX_STABLE)`; `make lib-test` green.

## Note — broader theme

This is one entry in the larger "grow pxx's `classes` toward FPC's `Classes`
surface" effort (the probe's dominant library blocker: `custapp`/`eventlog` also
want `TComponent` in `classes` rather than `classes_lite`). Keep those as
separate tickets; this one is the concrete, self-contained `TList.Notify` piece
that a real FPC unit (`contnrs`) hits first.
