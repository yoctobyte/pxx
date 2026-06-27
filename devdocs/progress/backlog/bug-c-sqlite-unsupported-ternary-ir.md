# C: sqlite hits unsupported `AN_TERNARY` during IR lowering

- **Type:** bug (C frontend / IR lowering) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after `getpid` and ternary-middle
  comma parsing were fixed.

## Symptom

sqlite now advances to:

```text
Unsupported linear node in IR codegen! Kind=10 node=2794 IRA=67 IRB=100111 IRC=100114 IRIVal=0
pascal26:56919: error: Unsupported linear node in IR codegen ()
```

`Kind=10` is `IR_UNSUPPORTED`; `IRA=67` is `AN_TERNARY`.

Repro:

```sh
./compiler/pascal26 -Ilibrary_candidates/sqlite library_candidates/sqlite/sqlite3.c /tmp/sqlite3
```

The reported preprocessed location is around `balance_deeper()` in btree code,
after the `getVarint32` parse wall is cleared.

## Notes

Ordinary value-bearing `AN_TERNARY` lowering exists in `IRLowerAST`, so this is
likely a ternary reaching a path that still routes to generic unsupported
lowering, or a source construct producing a ternary where an lvalue/address path
is expected. Needs focused reduction from the sqlite preprocessed source or IR
trace.

## Acceptance

- sqlite advances past the unsupported `AN_TERNARY` IR wall.
- A focused C regression captures the reduced source shape.
