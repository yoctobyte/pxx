# C: ternary middle arm rejects comma expression

- **Type:** bug (C frontend / expression parser) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after `getpid` cleared.
- **Closed:** 2026-06-27

## Symptom

sqlite advanced to a parse error in a macro-expanded `getVarint32` expression:

```c
((u32)(nPayload)<(u32)0x80)
  ? (*(&pCell[nHeader])=(unsigned char)(nPayload)), 1
  : sqlite3PutVarint(...)
```

The parser consumed only the assignment as the ternary middle arm and then
expected `:`, failing when it saw the comma before `1`.

## Cause

C's conditional operator grammar makes the middle arm a full `expression`, so a
top-level comma belongs to that arm. `ParseCExpr` used itself for the middle arm,
but top-level comma parsing lives in `ParseCCommaExpr`.

## Fix

Use `ParseCCommaExpr` for the `?:` middle arm.

## Regression

Added `test/cternary_middle_comma_b102.c`, wired into `make test-core`.
