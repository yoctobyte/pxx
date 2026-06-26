# LFM streaming and constructors

How the RTTI `.lfm` streaming loader instantiates objects, why it currently
breaks classes that do work in their constructor, how FPC avoids this, and the
decision for the proper fix.

Status: the four immediate bugs are fixed with stopgaps
(`devdocs/progress/done/bug-lfm-streaming-skips-constructors.md`). The proper fix is
ticketed urgent (`devdocs/progress/urgent/feature-streaming-run-constructor.md`).

## The streaming path

`{$R TFoo foo.lfm}` embeds the form's `.lfm` text as a resource. At runtime:

```
TFoo.Create
  -> InitInheritedComponent(Self, 'TFoo')        { lib/rtl/lfm.pas }
       FindResource('TFoo') -> the embedded bytes
       TLfmReader.Convert(...)                    { lfm text -> binary value stream }
       TReader.ReadRootComponent(Self, cls)       { lib/rtl/classes_lite.pas }
         for each `object Name: TKind` child:
           childInst := CreateInstance(GetClass('TKind'))   { typinfo.pas }
           read its published properties -> SetOrdProp / SetStrProp / SetMethodProp
```

`GetClass(name)` returns a `PClassRTTI` — a runtime class descriptor (name, VMT
pointer, parent link, published method table, published property table). It is,
in effect, a **metaclass expressed as data**.

## The defect: constructors never run

`CreateInstance` allocates and stamps the VMT, but does NOT run the constructor:

```pascal
obj := GetMem(cls^.InstanceSize);
{ zero the instance }                 { added 2026-06-23 }
PPointer(obj)^ := cls^.VMTPtr;
```

So whatever a class sets up in `Create` simply does not exist on a streamed
instance. The loader had only ever been exercised with a single `TButton`
(`test_pcl_lfm`), whose constructor only calls `HandleNeeded`, so this went
unnoticed until a real multi-widget form was streamed.

Four distinct failures resulted, all the same root cause:

1. Setter-method properties (`Caption`, `Left/Top/Width/Height`) never applied —
   `SetOrdProp`/`SetStrProp` only wrote direct-field props; the setter path was a
   no-op. (Adjacent issue: property *application*, not the constructor, but it hid
   the others.) Fixed: invoke the setter for `SetKind=1`.
2. `CreateInstance` assumed `GetMem` returns zeroed memory; reused heap left
   `FHandle` garbage. Fixed: zero the instance.
3. `TListBox`/`TComboBox` `SetLength` their `FItems` in the constructor → nil when
   streamed → `FItems[0]` crash. Fixed: grow on demand in `AddItem`.
4. `TPaintBox.Create` makes `FCanvas` → nil when streamed → the draw trampoline's
   `Canvas.Handle := cr` deref crashes under `gtk_main`. Fixed: make the Canvas in
   `CreateHandle`.

Diagnosis confirmed it was **lib (Track B)**, not resource inclusion (`{$R}`
embeds + reads fine — properties that streamed proved the bytes were intact) and
not the compiler (`GetMethodAddr` returns correct, distinct addresses).

## The tension

A constructor is *the* idiomatic place to establish required state, and a class
should be able to rely on it. Our stopgaps make widgets NOT rely on their
constructor (move init to `CreateHandle`, grow lazily). That is a workaround that
distorts the widgets around a streamer limitation — it inverts the rule. The
honest position: the streamer skipping constructors is the actual bug.

## How FPC solves it

Three language pieces, no manual pointer fishing:

1. **Virtual constructor:** `constructor Create(AOwner: TComponent); virtual;` —
   has a VMT slot, so a call through a class reference dispatches to the right
   derived constructor.
2. **Class references (metaclasses):** `TComponentClass = class of TComponent;`
   `RegisterClass(TButton)` maps `'TButton'` to the real, callable metaclass.
3. **The reader just calls it:** `GetClass(name).Create(Owner)` — a virtual-
   constructor call: `NewInstance` (virtual, allocates+zeroes) → the real
   constructor → then properties stream on top (defaults first, overrides second).

So in FPC the compiler generates the dispatch; allocation, zeroing and the
correct constructor all go through the VMT.

This project's `GetClass` returns a *data record* (`PClassRTTI`), not a Pascal
class reference, and there is no virtual-constructor / `class of` machinery — which
is exactly why `CreateInstance` hand-rolls allocation and skips the constructor.

## What already works (probed 2026-06-23)

`class of` is not greenfield. Metaclass aliases are pointer-backed and compile;
virtual constructors compile; **direct** construction is correct:

```pascal
TBaseClass = class of TBase;        { compiles }
o := TDer.Create;                   { direct virtual ctor -> tag=2, correct }
```

The one thing broken is **construction through a metaclass variable**:

```pascal
c := TDer;  o := c.Create;          { -> tag=4223806 (garbage) }
```

`c.Create` must dispatch through the value's VMT to allocate the *dynamic* class
and run its virtual constructor. That single dispatch is the gap — and it is
exactly what a component streamer needs (`classRef := metaclass(typeName);
obj := classRef.Create`).

## Decision — walk the rabbit hole, not the shortcut

We considered a parameterless `TClassRTTI.CtorPtr` (emit the ctor body address,
call by pointer). **Rejected.** It would unblock our streamer with less work but:

- it can never make FPC/LCL *source* compile (LCL uses `class of`, virtual
  `Create(AOwner)`, `RegisterClass`);
- it hard-codes "parameterless", and FPC's constructor is `Create(AOwner)` —
  owner-on-construct is intentional;
- it is throwaway once real metaclass construction lands.

And we are **not blocked**: Eliah works with the stopgaps, so there is no reason
to ship a dead-end. So: fix the real thing —
`urgent/feature-metaclass-construct-dispatch` (make `metaclassVar.Create` work) —
and let the streamer construct through a class-ref like FPC does.

## Ownership stance

We adopt the `Create(AOwner)` **shape** for compatibility but keep `Owner = nil`
first-class: in-app code may pass `nil` and just set `Parent` (a common, cleaner
pattern). Compatibility, not the auto-free religion. See
`backlog/feature-pcl-component-ctor-owner`.

## North-star

Someday compile parts of the actual LCL (even with our own CL). That is a
marathon — needs broad completeness (interfaces, generics, RTL breadth), and
`class of`+virtual-ctor is necessary-not-sufficient. But every brick toward it
(metaclass construction, virtual ctors, `Create(AOwner)`) is independently useful
for our own component library.

## Layering

1. **`metaclassVar.Create` dispatch** — urgent, Track A
   (`feature-metaclass-construct-dispatch`). The keystone.
2. **PCL `Create(AOwner)` + minimal Owner** — Track B
   (`feature-pcl-component-ctor-owner`). The library shape.
3. **Descendant-constraint enforcement / `object` root type** — existing backlog
   (`feature-metaclass-descendant-enforcement`, `feature-object-reference-type`),
   adjacent, reuse the same VMT plumbing.

When 1+2 land, the streamer calls `classRef.Create(owner)` and the four stopgaps
revert to idiomatic constructors.

## OO-compatibility analysis (does running the ctor via metaclass bite us?)

No tail-bite — running the constructor through metaclass dispatch is fully
compatible with the rest of the object model, often *more* faithful:

- **Virtual methods:** already correct on streamed instances — `CreateInstance`
  stamps the VMT at allocation, so dispatch works whether or not the ctor ran.
- **Inheritance / `inherited Create`:** the dispatched constructor is the most-
  derived body, which calls `inherited` as written — the chain runs, identical to
  a normal `TFoo.Create`. If the source omits `inherited`, that is faithful to the
  source, not a new bug.
- **Abstract methods:** a streamed instance is always a *concrete* class (the lfm
  names one), so its VMT has the real overrides — no "abstract method called".
  Abstract classes can't be streamed in FPC either.
- **Right ctor:** we look the class up by name and dispatch through *its* VMT, so
  we always run the correct concrete constructor — same outcome FPC's virtual
  constructor gives.
- **Default values:** ctor sets defaults, then properties override only what the
  lfm specifies — this *improves* fidelity over the current zero-only behaviour.

The real constraint is the **parameter**: FPC's ctor is `Create(AOwner)`. The
dispatch must pass the arg through (not assume parameterless) — hence the
companion `feature-pcl-component-ctor-owner`. Benign side effect: PCL ctors call
`HandleNeeded`, so running them at stream-time builds the (unparented) widget a
bit early — idempotent (`if FHandle=nil`), harmless.

## Until then

The stopgaps stay (harmless defaults-hardening) and Track B keeps shipping. The
contract — "a streamable class must not rely on its constructor; init in
`CreateHandle`/lazily" — is documented at `lib/rtl/typinfo.pas:CreateInstance` as
a **stopgap until 1+2 land**, not the permanent rule.
