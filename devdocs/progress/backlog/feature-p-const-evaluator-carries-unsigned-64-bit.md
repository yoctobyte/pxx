---
track: P
prio: 48
type: feature
blocked-by: []
summary: "`High(QWord)`, `Low(UInt64)`, `High(NativeUInt)` and `High(PtrUInt)` are rejected at compile time — the const evaluator carries Int64, which cannot hold 2^64-1. Every other integer type name folds. Idiomatic FPC code that spells a machine-word bound this way does not compile."
status: backlog
owner: unassigned
---

# The const evaluator cannot carry an unsigned 64-bit bound

- **Track P** (`OrdinalTypeBound` / the fold pipeline in `parser.inc`).
- Split out 2026-08-20 from `bug-p-str-of-a-qword-formats-it-signed`, where a
  probe hit it; the refusal itself dates from
  `bug-p-high-low-reject-the-64-bit-type-aliases` (2026-08-16) and is
  deliberate.

## Repro

```pascal
writeln(High(QWord));      { pascal26: error: undefined variable (QWord) }
writeln(High(NativeUInt)); { same }
writeln(High(PtrUInt));    { same }
writeln(High(UInt64));     { same }
```

FPC answers `18446744073709551615` for all four. Every OTHER integer type name
folds correctly in pxx today — Integer, Int64, LongWord, Word, Byte, ShortInt,
SmallInt, Cardinal, LongInt, NativeInt, PtrInt, Boolean, Char — measured.

## Why it is refused rather than wrong

`OrdinalTypeBound` returns the bound in an `Int64`, and `ASTIVal` is an `Int64`.
2^64-1 does not fit; storing it as -1 and tagging the literal `tyUInt64` would
print correctly (the write paths dispatch on signedness) but would fold WRONG
the moment the value entered const arithmetic — `High(QWord) div 2` would be 0,
not 2^63-1. The previous session chose the honest refusal, and that call stands
until the evaluator can represent the value.

## What the fix actually is

A representation change in the const evaluator, not a missing table row: carry
an unsigned flag alongside the `Int64` (or a 128-bit intermediate) and teach
the fold operators to respect it. Then the four names are one table row each.

## Scope check before starting

Grep the fold sites (`TryConstHighLowValue`, `TryFoldHighLowType`,
`OrdinalTypeBound`, the binop folder) — the flag has to reach every one of them
or the refusal is better than a partial answer.
