# LFM streaming and constructors

How the RTTI `.lfm` streaming loader instantiates objects, why it currently
breaks classes that do work in their constructor, how FPC avoids this, and the
decision for the proper fix.

Status: the four immediate bugs are fixed with stopgaps
(`docs/progress/done/bug-lfm-streaming-skips-constructors.md`). The proper fix is
ticketed urgent (`docs/progress/urgent/feature-streaming-run-constructor.md`).

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

## Decision

We do NOT need to build `class of` to fix this. We already mimic a metaclass:
`PClassRTTI` + `CreateInstance` + `IsSubclassOf` + `GetMethodAddr` are the
metaclass operations, spelled as an explicit handle + free functions instead of
typed syntax.

**Make that handle a real factory: add `TClassRTTI.CtorPtr`** (compiler emits the
parameterless-constructor *body* entry point) and have `CreateInstance` call it
after allocating + zeroing, before properties stream. Calling is the same
call-by-code-pointer already used for setter methods (`Self` in rdi).

```
function Construct(cls): Pointer;
begin
  Result := alloc + zero + VMT;
  if cls^.CtorPtr <> nil then CallCtor(Result, cls^.CtorPtr);  { runs the ctor body }
end;
```

Why this and not `class of`:

- **Zero source changes.** Widgets keep plain `constructor Create;` —
  FPC-source-compatible. The Canvas/array stopgaps revert to constructors.
- **FPC's behaviour, not FPC's plumbing.** Ctor runs → props override, in ~6 lines
  of RTL + one RTTI field.
- **`class of` is sugar over this same runtime.** A `class of T` value is just a
  `PClassRTTI`/VMT pointer; `c.Create` is `Construct(c)`; `obj is c` is the
  parent-chain walk we already have. So if real `class of` lands later
  (`feature-object-reference-type`), it REUSES `CtorPtr` — option 1 is a
  prerequisite, never wasted.

Gotcha: emit/call the constructor **body** (init on a pre-allocated `Self`), not
the alloc-and-init entry, or you double-allocate. The compiler already splits
these (that is how `inherited Create` runs a parent body without re-allocating).
These constructors call `HandleNeeded` (`if FHandle=nil`), so running them at
stream-time then again at Realize is idempotent.

## Layering (do not conflate)

1. **Runtime factory — `CtorPtr` (urgent, Track A).** Fixes streaming, lets the
   stopgaps revert. `feature-streaming-run-constructor`.
2. **Syntax — `class of` + virtual constructors (later, optional).** Typed sugar
   for source code that wants FPC-style component registration; builds on (1).
   `feature-object-reference-type`, `feature-metaclass-descendant-enforcement`.

## Until then

The stopgaps stay (harmless defaults-hardening) and Track B keeps shipping. The
contract — "a streamable class must not rely on its constructor; init in
`CreateHandle`/lazily" — is documented at `lib/rtl/typinfo.pas:CreateInstance` as
a **stopgap until (1) lands**, not as the permanent rule.
