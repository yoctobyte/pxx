# Built-in / RTL `Exception` base class

- **Type:** feature (compiler / RTL)
- **Status:** DONE 2026-06-21 (RTL `Exception` base in `lib/rtl/sysutils.pas`;
  chess compiles past `class(Exception)`, now blocks further down on
  `feature-local-typed-constant` at `chess.pas:846`)
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
- 2026-06-20 — Added to `make library-suite-discovery` as `demo_chess`.
  Current pinned v18 output remains `base type not found: Exception`; the suite
  tags it as Track B if a minimal RTL `Exception` class is sufficient, Track A
  if default-scope / exception-runtime behavior needs compiler support.
- 2026-06-20 — Track B slice implemented in `lib/rtl/sysutils.pas`, matching
  FPC's home for the base class: `Exception = class` with `Message`,
  `HelpContext`, and `Create(const msg)`. `test/lib_sysutils.pas` now verifies
  inherited construction, property access, `raise`, and typed catch via a local
  descendant.
- 2026-06-20 — Verified `make library-suite` green with the SysUtils base class.
  `demo_chess` now gets past the missing base class and fails on the next FPC
  syntax gap, `EChess = class(Exception);` as an empty descendant shorthand.
  Tracked separately in `feature-empty-class-shorthand`.
- 2026-06-21 — CLOSED. `feature-empty-class-shorthand` landed (in done/), so
  `EChess = class(Exception);` now parses. Reconfirmed: `./compiler/pascal26
  -Fulib/rtl -Fulib/pcl examples/chess/chess.pas` no longer errors on `Exception`
  — it advances to `chess.pas:846` (`local typed constant not supported`), tracked
  in `feature-local-typed-constant`. Acceptance met: chess past the base class;
  raise/catch `class(Exception)` covered by `test/lib_sysutils.pas`; `make test`
  green. → done/.
