# FPC seed build fails after Lua C frontend helper additions

- **Type:** bug
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27 during Track C Lua compiler stability check

## Symptom

`make bootstrap` currently fails in the initial FPC seed compile before the
self-host stages:

```text
symtab.inc(979,27) Error: Identifier not found "TypeSize"
ir.inc(901,15) Error: Identifier not found "CNodeDecaysToPointer"
```

This is not a self-host stability failure. It is an include-order / forward
declaration issue exposed by helper calls added during the Lua C frontend work:

- `RecFieldRowStride` in `symtab.inc` calls `TypeSize` before `TypeSize` is
  declared for FPC.
- `IRNodePointerBase` in `ir.inc` calls `CNodeDecaysToPointer`, but `cparser.inc`
  is included after `ir.inc` in `compiler.pas`.

Self-hosted `compiler/pascal26` has historically accepted this shape, but FPC
does not. Fix should preserve the include model and avoid moving large chunks
unless necessary.

## Log

- 2026-06-27 - Captured from failed `make bootstrap` seed compile. User confirmed
  FPC seeding is not required for the current push, but this should be fixed.
