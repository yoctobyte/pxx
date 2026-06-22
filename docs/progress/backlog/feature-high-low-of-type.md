# `High`/`Low` of an ordinal TYPE (e.g. `High(Byte)`, `Low(ShortInt)`)

- **Type:** feature (language) — Track A
- **Status:** backlog
- **Opened:** 2026-06-23
- **Found by:** differential probe vs FPC.

## Problem

`High`/`Low` only accept an array VARIABLE. `High(Byte)` etc. (an ordinal type)
errors `High: expected array variable`. (Also note `Byte` lexes as a type-keyword
token, and there is no `tkLow` — `Low` isn't handled at all.)

```pascal
begin writeln(High(Byte)); end.   // pxx: error;  fpc: 255
```

## Fix

`High(T)` / `Low(T)` of an ordinal type fold to compile-time constants: built-in
ordinals (Byte 0..255, ShortInt -128..127, Word, SmallInt, Integer, Cardinal,
LongWord, Int64/UInt64, Char 0..255, Boolean 0..1) and user enums (0..N).
Needs: accept type-name tokens / type idents as the High/Low arg, a type-range
table, and a `Low` builtin (no `tkLow` today). Parser-level, single-point (all
backends). Gate: `make test` + FPC oracle.
