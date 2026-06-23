# bug: explicit `class(TObject)` base "type not found"

- **Type:** bug (Track A — symbol resolution)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low-medium (common FPC/Delphi spelling; blocks `class(TObject, IFoo)`)

## Symptom

Naming `TObject` explicitly as the base class fails, though an implicit base
works:

```pascal
type tc = class(TObject) procedure m; end;   { pxx: error: base type not found: TObject }
type tc = class procedure m; end;            { ok (implicit TObject base) }
```

Also blocks the interface-with-explicit-base form `class(TObject, IFoo)` and
`class(TInterfacedObject, IFoo)` (TInterfacedObject likewise "not found").

## What works

- A plain `class` (implicit TObject) — methods, fields, virtual/override all fine.
- Interfaces: `tc = class(IFoo)` (interface as the sole parent, implicit TObject)
  compiles and dispatches correctly.

So `TObject` (and `TInterfacedObject`) just are not registered as nameable base
symbols; only the implicit/interface forms resolve.

## Expected

`TObject` is a real, nameable root class; `class(TObject)` and
`class(TObject, IFoo)` resolve to it (FPC).

## Repro

`type tc = class(TObject) procedure m; end; ...` → base type not found.
