# feature: PCL components adopt the `Create(AOwner)` virtual-constructor shape

- **Type:** feature (Track B — lib/pcl component model)
- **Status:** DONE 2026-06-24 (commit e71cb1c) — shape migrated + streamer adopts
  the metaclass virtual ctor; the four constructor-skip stopgaps are reverted.
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

## Progress 2026-06-23

DONE (the migration, which the ticket says can proceed independently):
- `classes_lite.TComponent.Create` → `constructor Create(AOwner: TComponent);
  virtual;` + `FOwner`/`Owner` + `TComponentClass = class of TComponent`.
- All PCL widgets migrated to `Create(AOwner); override;` calling
  `inherited Create(AOwner)`: controls.TControl, stdctrls (7), extctrls
  (TPanel/TTimer/TPaintBox/TPaned), menus (TMenuItem/TMenu), forms.TForm,
  glarea.TGLArea. graphics.* and TApplication stay parameterless (not components).
- All widget `.Create` call sites across apps/examples/test/gui pass an owner
  (nil — owner-less + Parent is first-class here). Form subclasses with their own
  ctor (TMainForm) became `Create(AOwner); override;`.
- gui_suite green (incl. streaming tests, paned, eliah), garin 92/92, eliah
  builds + smoke + screenshot.

BLOCKED — streamer adoption: replacing `CreateInstance` with
`TComponentClass(childCls).Create(parent)` and dropping the four
constructor-skip stopgaps. The metaclass-construct bridge stamps a non-canonical
VMT → `urgent/bug-metaclass-new-getclass-vmt`. Streamer stays on CreateInstance +
stopgaps (markers point at that ticket) until it lands.

Compiler gaps also hit (clean single-ctor path used instead, no workaround):
default param on a constructor and overloaded constructors + `inherited` both
fail to parse — noted for a future backlog ticket if the parameterless-convenience
shape is ever wanted.

## Progress 2026-06-24 — streamer adoption DONE

`done/bug-metaclass-new-getclass-vmt` (v45) cleared the block. `TReader.ReadChildren`
now constructs each child via `TComponentClass(childCls).Create(parent)` (Owner =
parent), so streamed components run their real virtual ctors. All four
constructor-skip stopgaps reverted:
- TPaintBox.CreateHandle FCanvas=nil guard removed (ctor sets Canvas);
- TListBox/TComboBox FItems grow-on-demand kept only as plain robustness past the
  ctor's initial 256 reservation (stopgap rationale comment dropped);
- typinfo.CreateInstance STOPGAP CONTRACT note rewritten — the raw allocator now
  serves only the root-form load path (TApplication.CreateForm) + RTTI tests that
  deliberately skip the ctor.

Gates: garin 116/116, gui_suite OK (incl test_pcl_lfm streaming), eliah
build+smoke+screenshot green. Commit e71cb1c.
