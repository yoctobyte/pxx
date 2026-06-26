---
title: FPC compatibility
order: 45
---

# FPC compatibility

PXX aims to compile a useful FPC/Object Pascal-like subset. It does not claim
full FPC language, RTL, package, object-file, or command-line compatibility.

## What usually ports well

Small Pascal programs using ordinary declarations, routines, records, arrays,
classes, basic generics, exceptions, and simple units are the best fit.

`{$mode objfpc}` and `-Mobjfpc` are accepted as compatibility markers. PXX does
not currently implement multiple Pascal semantic modes.

## Identity symbols

| Symbol | Meaning |
| --- | --- |
| `PXX` | Defined by PXX. |
| `FPC` | Not defined by PXX. Reserved for actual Free Pascal builds. |

Use this pattern for compiler-specific code:

```pascal
{$ifdef PXX}
  { PXX-specific path }
{$endif}

{$ifdef FPC}
  { Free Pascal-specific path }
{$endif}
```

## Important differences

- The FPC RTL and package ecosystem are not bundled as compatible units.
- The CLI is PXX-specific; it does not emulate the full FPC command line.
- Unit/object/package binary compatibility with FPC is not provided.
- Some FPC directives are accepted only as comments or compatibility markers.
- Overflow, range checking, and many compile-switch states are not implemented.
- Only tested project units and examples should be treated as supported.

## Next

- [PXX dialect](./dialect.md)
- [Reference](../reference/)
