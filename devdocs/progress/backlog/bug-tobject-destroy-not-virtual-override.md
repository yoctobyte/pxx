# Built-in TObject has no virtual `Destroy`/`Create` to `override` — breaks the universal FPC idiom

- **Type:** bug (compiler object model — Track A)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-04 (found in the FPC/LCL compile probe,
  [[fpc-lcl-compile-probe]])
- **Relation:** sibling of the done [[bug-explicit-tobject-base]] (that made
  `class(TObject)` a nameable base; this is the method-slot half) and
  [[bug-method-call-free-tobject]] (`obj.Free` — same "built-in TObject is
  method-less" root). All three are pxx's minimal implicit root vs FPC's real
  `TObject`.

## Problem

FPC's `TObject.Destroy` is **virtual**, so the universal Object Pascal idiom is:

```pascal
type TFoo = class
  destructor Destroy; override;      // every non-trivial FPC class does this
end;
destructor TFoo.Destroy; begin ...; inherited Destroy; end;
```

pxx rejects it:

```
pascal26: error: cannot override: no virtual method found in parent chain: Destroy
```

Same for a virtual constructor (`constructor Create; override;` — needed by
`TComponent` descendants, whose `Create(AOwner)` is virtual):

```
pascal26: error: cannot override: no virtual method found in parent chain: Create
```

pxx's implicit root (parentCi = -1) is **method-less**: `TObject`/`TInterfacedObject`
are accepted as base *names* (bug-explicit-tobject-base) but carry no method
table, so there is no virtual `Destroy`/`Create` slot for a user override to bind
to. The override check at `parser.inc:12244` walks the parent chain, finds
nothing, and errors.

## What already works (so the gap is narrow and specific)

- `TFoo.Create`, `f.Free`, and a non-`override` `destructor Destroy;` all compile
  and run (pxx synthesises construct/free/destroy behaviour for the implicit
  root — see `parser.inc:7379` `obj.Free` desugar, `10241`).
- `virtual`/`override` on **user-declared** methods works when a parent in the
  chain declares the `virtual` slot.

So only the *root-provided* virtual `Destroy`/`Create` slots are missing.

## Why it matters

This is a top FPC-compatibility showstopper for real RTL/FCL source: `destructor
Destroy; override;` is in essentially every stateful FPC class. Measured in the
probe: `contnrs`, `inifiles` (and everything descending from their classes) wall
here immediately, independent of the separate TComponent library-placement gap.
Fixing it unblocks a large fraction of FPC RTL/FCL classes at once.

## Direction (pick during build)

- **A — give the implicit root a real virtual method table.** Register a builtin
  `TObject` class with a `virtual Destroy` (and the constructor machinery so a
  virtual `Create` can be overridden), so override binds normally and the VMT is
  laid out for it. Most faithful; touches symtab/VMT + the implicit-root path.
- **B — accept `override` on `Destroy`/`Create` of a root-derived class as
  binding to the synthesised root behaviour** (lenient front-end special-case),
  without a full root VMT. Smaller, but must still emit a real virtual dispatch
  so `inherited Destroy` and polymorphic `Free` (destroy-through-base-ref) work.

Either must keep `inherited Destroy`/`inherited Create` working and not regress
the existing non-`override` destructor path or self-host byte-identity.

## Acceptance

- `type TFoo = class destructor Destroy; override; end;` (both implicit base and
  explicit `class(TObject)`) compiles; `inherited Destroy` works; `Free` on a
  base-typed reference dispatches to the derived `Destroy` (polymorphic destroy).
- `constructor Create; override;` on a root-derived class compiles and dispatches
  virtually (covers `TComponent.Create(AOwner)` descendants).
- Regression test (`.pas`) that fails on today's master and passes after.
- Self-host byte-identical; `make test` green.
