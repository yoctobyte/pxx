# `High`/`Low` of an ordinal TYPE (e.g. `High(Byte)`, `Low(ShortInt)`)

- **Type:** feature (language) — Track A
- **Status:** done
- **Opened:** 2026-06-23
- **Closed:** 2026-06-23
- **Found by:** differential probe vs FPC.

## Resolution (2026-06-23)

Single-point parser fix (front-end only, no codegen — folds to `AN_INT_LIT`).
New `tkLow` token (lexer, length-3, case-insensitive; no `low` identifier
collision in compiler/lib/test/examples). New `OrdinalTypeBound` /
`OrdinalNameToTk` / `TryFoldHighLowType` helpers in `compiler/parser.inc`.

`High(T)`/`Low(T)` now fold for: the dedicated type tokens (Integer/Byte via
`tkInteger_T`, LongWord, Boolean, Char), the ordinal names that lex as `tkIdent`
(ShortInt, SmallInt, Word, Cardinal, LongInt, Int64, uint8/16/32), ordinal type
aliases (`AliasTk`), and user enums (`FindEnumType` → 0..count-1). A name that
resolves to a variable falls through to the existing array path; `Low(array)`
is 0 (pxx is 0-based), `High(array)` unchanged. UInt64/NativeInt `High` left
unsupported (value overflows signed `Int64` storage) — follow-up if needed.

Output byte-identical to FPC `{$mode objfpc}` across 19 probe cases (incl.
`High(Integer)=2147483647` — pxx Integer is 32-bit, verified by wrap probe).
Gate: `make test` (self-host byte-identical, no reseed — front-end only) + FPC
oracle.

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
