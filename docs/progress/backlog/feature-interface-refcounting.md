# Interface reference counting (IInterface / ARC)

- **Type:** feature
- **Status:** backlog — **GREENLIT, scope locked (2026-06-19)**. Next track-A
  big feature; pick up in a fresh context.
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (split from feature-interfaces)

## Decision (2026-06-19) — greenlit despite the earlier defer

Not a blocker (the reality-check below stands: no RTL we port depends on it).
Greenlit anyway because the cost collapsed once the substrate landed — CORBA
interfaces (fat-pointer + IMT + is/as/Supports + by-ref ABI, all 4 targets) and
the full managed-lifetime machinery are done, and ARC interfaces are the **same
shape as managed strings with a different finalizer** (`_Release` through the IMT
instead of the string decref). Doing it also retires the "ARC later" caveat that
keeps reappearing across interface/object/zero-init tickets. Framed as a
now-cheap idiom, not an unblock.

## What this is (and is NOT)

This is the **language** feature of automatically reference-counted interfaces —
`IInterface`/`IUnknown` with compiler-inserted `_AddRef`/`_Release`, deterministic
lifetime, no manual `.Free`. It is **not** Windows COM (no IUnknown binary ABI
across DLLs, no registry, no `CoCreateInstance`, no marshalling/apartments). The
"COM ARC" label on the old feature-interfaces ticket conflated the two; on Linux
the binary-COM machinery has no use, but ARC interfaces are FPC/Delphi/Lazarus
bread-and-butter and fully platform-independent.

## Reality check — do we need it? (2026-06-19)

**No, not soon.** Initial claim that "the FPC RTL leans on interfaces heavily"
was wrong (checked: fpjson, fgl, most fcl-* are plain class OOP with manual
`Free`). FPC *core* RTL uses interfaces only narrowly: `Classes`
(`IInterface`/`IUnknown`, `TInterfacedObject`, `IInterfaceList`,
`IFPObserved`/`IFPObserver`), the variants plumbing, and the Windows-only
ActiveX/COM units. The genuine interface+ARC payoff lives in the **Delphi**
ecosystem — smart-pointer/auto-free idiom, DI containers (Spring4D) — not in
anything PXX plans to port.

So the value here is one nice-to-have idiom (deterministic auto-free via interface
value lifetime), **not** an RTL dependency. The CORBA surface already done
(2026-06-19) covers polymorphic abstraction. This stays parked until a concrete
need appears.

## Scope

- `{$interfaces com}` (or default) mode alongside the existing CORBA mode.
- `IUnknown`/`IInterface` with the three reserved slots: `QueryInterface`,
  `_AddRef`, `_Release` (the latter two refcount the implementor).
- `TInterfacedObject` base: refcount field, `_AddRef`/`_Release` bump/drop it and
  `Free` at zero, `QueryInterface` via the existing closed-world IMT lookup.
- Compiler-inserted ARC: AddRef on interface-typed assign / by-value param / func
  result capture; Release on overwrite, scope exit, and exception unwind.
- Casting a class to a COM interface calls `_AddRef`; `nil`-assign releases.

## Substrate already in place (reuse, don't rebuild)

- CORBA fat-pointer `{IMT, instance}`, `is`/`as`/`Supports`, dynamic IMT lookup,
  interface inheritance, identity, by-ref param ABI (all 4 targets) —
  feature-interfaces, done 2026-06-19.
- Managed-lifetime machinery: managed-string `IncRef`/`DecRef`, scope-exit
  cleanup, exception-unwind finalisation, prologue nil-init of managed locals.
  Interface ARC is the same shape with a different finalizer (call `_Release`
  through the IMT instead of the string decref).

## Locked decisions (2026-06-19)

These resolve the prior "open questions"; implement to these, don't re-litigate.

1. **Mode selection.** `{$interfaces com}` opt-in directive enables ARC; **PXX
   default stays `corba`** (no refcounting) — zero behaviour change for existing
   code. `{$interfaces corba}` is the explicit form of the current default.
2. **Refcount location.** A refcount field in `TInterfacedObject` (FPC way), not
   a hidden side-table keyed off the instance.
3. **Release path.** Through the IMT `_Release` slot. COM-mode interfaces reserve
   the three leading IMT slots in declaration order: `QueryInterface`, `_AddRef`,
   `_Release`. `TInterfacedObject` implements all three; `_AddRef`/`_Release`
   bump/drop the field and `Free` at zero; `QueryInterface` reuses the existing
   closed-world IMT lookup.
4. **ARC insertion points.** Reuse the managed-local finalizer path. `_AddRef` on
   interface-typed assign / by-value param / function-result capture; `_Release`
   on overwrite, scope exit, exception unwind, and `nil`-assign. Casting a class
   to a COM interface calls `_AddRef`.
5. **Threadsafe.** Atomic inc/dec on the refcount field under `--threadsafe`
   (mirror the managed-string atomic path).

Default-corba means the whole feature is gated behind `{$interfaces com}`, so a
mistake cannot regress existing CORBA-interface or class code — a useful safety
rail while landing it across 4 targets.

## Acceptance

`TInterfacedObject`-derived class managed purely through interface variables (no
manual Free) frees exactly once at the last reference drop; ARC correct across
assign / param / result / scope-exit / exception; self-host + cross-bootstrap
byte-identical.

## Log

- 2026-06-19 — split from feature-interfaces (CORBA surface complete). Renamed
  away from "COM ARC" to name the actual feature.
- 2026-06-19 — reality-checked and **deferred**. The "FPC RTL needs interfaces"
  premise was false (fpjson etc. are plain OOP); real ARC value is a Delphi-side
  smart-pointer idiom we don't need. Parked for a rainy afternoon.
- 2026-06-19 — **greenlit, scope locked.** Still not a blocker, but cheap now
  (CORBA + managed-lifetime substrate done; ARC = same shape, different
  finalizer) and it retires the recurring "ARC later" caveat. Five decisions
  locked (mode/refcount-location/release-path/insertion-points/threadsafe);
  default stays corba so it can't regress existing code. Pick up in a fresh
  track-A context.
