# Interface reference counting (IInterface / ARC)

- **Type:** feature
- **Status:** backlog (next interface arc after CORBA surface completed 2026-06-19)
- **Owner:** —
- **Opened:** 2026-06-19 (split from feature-interfaces)

## What this is (and is NOT)

This is the **language** feature of automatically reference-counted interfaces —
`IInterface`/`IUnknown` with compiler-inserted `_AddRef`/`_Release`, deterministic
lifetime, no manual `.Free`. It is **not** Windows COM (no IUnknown binary ABI
across DLLs, no registry, no `CoCreateInstance`, no marshalling/apartments). The
"COM ARC" label on the old feature-interfaces ticket conflated the two; on Linux
the binary-COM machinery has no use, but ARC interfaces are FPC/Delphi/Lazarus
bread-and-butter and fully platform-independent.

## Why FPC's RTL leans on it

(populate from the FPC reading) — smart-pointer idiom, value-semantics object
lifetime, `TInterfacedObject`, fpjson / Lazarus / LCL usage, etc.

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

## Open questions to lock first

- Per-instance refcount location: a field in `TInterfacedObject`, or a hidden
  slot keyed off the instance? (FPC: field in the object.)
- CORBA vs COM selection: directive-driven (`{$interfaces}`) per FPC, and what
  the PXX default should be.
- Whether a fat-pointer interface value's Release goes through IMT slot 2
  (`_Release`) — needs the reserved leading slots in COM-mode interfaces.
- Threading: refcount atomicity under `--threadsafe`.

## Acceptance

`TInterfacedObject`-derived class managed purely through interface variables (no
manual Free) frees exactly once at the last reference drop; ARC correct across
assign / param / result / scope-exit / exception; self-host + cross-bootstrap
byte-identical.

## Log

- 2026-06-19 — split from feature-interfaces (CORBA surface complete). Renamed
  away from "COM ARC" to name the actual feature.
