---
track: A
prio: 45
type: feature
blocked-by: []
summary: "__pxxGetInterface stores the instance pointer into the caller's interface variable without an AddRef, so the slot holds a borrowed reference while the compiler treats the variable as managed and releases it at scope exit. Every Supports/GetInterface hit is therefore one release the object never got a retain for. Nothing observed to crash yet, which is why it is a ticket and not an urgent bug — but the asymmetry is real and worth settling deliberately."
---

# `GetInterface` / `Supports` hand back a borrowed reference into a managed slot

- **Type:** feature / correctness question — Track A
  (`compiler/builtin/builtin.pas`, and whatever the interface-var lowering does).
- **Status:** backlog
- **Opened:** 2026-08-21, noticed while fixing
  `bug-a-an-interface-name-as-a-guid-value-copies-rtti`.

## The asymmetry

`__pxxGetInterface(Instance, IID, Obj)` writes through a raw `Pointer`:

```pascal
outp := PPxxPtr_(Obj);
outp^ := Instance;
```

No `_AddRef`. The write is invisible to the managed-variable machinery, so:

- on the **way in**, an interface variable that already held a reference is
  overwritten without a release (the nil-on-failure store added by the GUID
  ticket is a plain store for exactly this reason — releasing there would
  over-release a borrowed pointer);
- on the **way out**, the compiler still treats the variable as a managed
  interface and releases it at scope exit.

So a successful `Supports(o, IFoo, f)` in a procedure body is one release
against zero retains. With a `TInterfacedObject` whose lifetime is owned
elsewhere this is invisible; with one whose only reference is `f`, it is an
early free.

## Why it has not bitten

Every use in this repo's tests and corpora reaches the object through some other
owning reference, so the count never crosses zero at the wrong moment. The
differential that found the GUID bug also could not make it crash — a contrived
attempt produced a *divergence in FPC's favour* only because FPC's own
`Supports` releases its temporary and destroys the object, which is the correct
behaviour pxx does not reproduce.

## Options

1. **AddRef in `__pxxGetInterface` on success**, and release the old value
   first. Correct, and it makes the slot a real owning reference — but it needs
   the *old* value to be a real owning reference too, which it is not today for
   a slot a previous `GetInterface` filled. Sequencing matters.
2. **Lower `Supports`/`GetInterface` through the managed-assignment path**
   instead of a raw store, so the ordinary retain/release rules apply and the
   helper stops touching the slot directly. Bigger, and the right shape.
3. **Leave it and document the borrow.** Defensible only if the dialect states
   it, which would diverge from FPC.

Recommendation: option 2, with option 1 as the cheap interim if something starts
crashing. Either way it wants a repro first — a `TInterfacedObject` whose sole
reference comes from `Supports` and which is expected to survive to the end of
the scope.
