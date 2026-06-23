# Set literal in a `const` declaration (`const S = [1,2,3]`)

- **Type:** feature (parser/const) — Track A
- **Status:** backlog
- **Opened:** 2026-06-23
- **Found by:** differential probe vs FPC.

## Problem

A set constant fails to parse ("unexpected token"):

```pascal
const S = [1,2,3];           // pxx: error;  fpc: ok
type TS = set of 1..9; const S: TS = [1,2,3];   // also fails
begin if 2 in S then ... end.
```

A `var` set assigned a `[...]` literal at runtime works; only the `const`
declaration form is unhandled.

## Fix

Accept a `[...]` set literal as a constant initializer and store it as a
compile-time set bitmask (the same blob a runtime set uses), so `in` / set ops
read it like any set constant. Needs const-expr handling for set literals + a
const-set data representation. Gate: `make test` + FPC oracle.

## Related (Track B, noted)

`LowerCase`/`UpperCase`/`Trim` (string-case SysUtils funcs) are also missing
without `uses sysutils` — those belong in `lib/rtl/sysutils` (Track B), unlike
the System char/ordinal intrinsics (UpCase, Succ/Pred/Odd, Abs/Sqr, Pos) added
this session.
