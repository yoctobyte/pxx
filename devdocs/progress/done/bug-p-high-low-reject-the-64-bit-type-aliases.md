---
track: P
prio: 40
type: bug
blocked-by: []
summary: "`High(NativeInt)` / `High(PtrInt)` / `High(SizeInt)` were refused with \"expected an ordinal type name\" while `High(Int64)` folded — the names already mapped to a kind, but OrdinalTypeBound had no row for tyNativeInt and SizeInt had no name mapping at all."
status: done
---

# High/Low reject the 64-bit type aliases

- **Type:** bug (refusal, FPC-compat) — **Track P**, in the shared
  `compiler/parser.inc`, so it runs under Track A's gate.
- **Found:** 2026-08-16, by an FPC-differential sweep over the built-in type
  names.

## Measured (before)

```
High/Low(NativeInt)   fpc 9223372036854775807 / -9223372036854775808   pxx refused
High/Low(PtrInt)      same                                             pxx refused
High/Low(SizeInt)     same                                             pxx refused
High/Low(Int64)       same                                             pxx ok
```

`SizeOf(v)` for every one of those names was already right, so this was
specifically the High/Low fold — which is also what sizes an array
(`array[0..High(PtrInt) shr 62]`) and what a machine-word bound in a `const`
is spelled with.

## Fix

`OrdinalTypeBound` gains a `tyNativeInt` row (Int64's bounds — this target's
machine word), and `OrdinalNameToTk` gains `sizeint`, which had no mapping at
all.

The UNSIGNED 64-bit names — QWord, UInt64, NativeUInt, PtrUInt — are still
refused, deliberately: their High is 2^64-1, which the constant evaluator's
`Int64` cannot carry, and answering -1 would turn a refusal into a wrong value.
That is a representation change in the const evaluator, not a missing row.

## Result

`test/test_high_low_word_aliases.pas` — the three aliases, the four bounds that
already worked, and the fold in `const` and array-bound position — prints
`total ok 12 / 12` under both FPC 3.2.2 and pxx.

## Gate

`make compiler/pascal26` + the test under both compilers + `tools/gate.sh
quick` — GREEN.

## Log
- 2026-08-16 — resolved, commit 6bc4333d0.
