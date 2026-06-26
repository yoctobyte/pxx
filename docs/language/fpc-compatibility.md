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

## Porting checklist

Start with a small, direct compile:

```sh
./pxx program.pas program
```

If the program uses local units, add their directories explicitly:

```sh
./pxx -Fusrc -Fusrc/common program.pas program
```

For code that probes FPC identity symbols or expects FPC-style conditional
branches, try the curated compatibility define set:

```sh
./pxx --mimic-fpc -Fuvendor/lib program.pas program
```

`--mimic-fpc` is opt-in. It is meant for FPC-oriented library code that chooses
implementation branches by compiler identity. Do not use it as a blanket default
for every PXX project, and do not use it to decide whether code is running under
real Free Pascal.

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

## Common fixes

Prefer these changes when moving small FPC examples to PXX:

- Replace implicit package assumptions with explicit `uses` clauses and `-Fu`
  search roots.
- Keep compiler-specific branches under `{$ifdef PXX}` or `{$ifdef FPC}`.
- Avoid depending on FPC's full RTL surface unless the needed unit exists in
  `lib/rtl`.
- Build C-header or imported-library experiments separately from the first
  Pascal port; get the Pascal-only slice compiling first.

## Next

- [PXX dialect](./dialect.md)
- [Reference](../reference/)
