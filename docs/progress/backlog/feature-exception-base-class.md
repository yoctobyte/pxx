# Built-in / RTL `Exception` base class

- **Type:** feature (compiler / RTL)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20 (demo dashboard against pinned v14)
- **Relation:** blocks `feature-demo-chess` and any FPC-style code that declares
  exception classes as descendants of `Exception`.

## Symptom

`examples/chess/chess.pas` fails to compile against pinned stable v14:

```text
pascal26:85: error: base type not found: Exception ()
```

The source declares:

```pascal
EChess = class(Exception);
```

PXX already supports raising class instances and typed `on E: TClass do`
handlers (`test/test_exception_typed.pas`), but there is no canonical
`Exception` class in the default scope / RTL.

## Scope

- Provide a minimal FPC-style `Exception` base class usable as
  `class(Exception)`.
- Keep existing class-object exception behavior working.
- Decide whether the class lives in the builtin namespace, `sysutils`, or both
  via compiler prelude / default import rules.

## Acceptance

- `examples/chess/chess.pas` gets past `EChess = class(Exception)`.
- Existing exception tests still pass, especially `test/test_exception_typed.pas`.
- A small regression test can declare, raise, and catch `class(Exception)`.

## Log
- 2026-06-20 — Opened after `make demos` on pinned v14 failed on chess.
