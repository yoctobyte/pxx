---
track: A
prio: 55
type: bug
blocked-by: []
status: done
owner: claude-A
---

# `Low`/`High` of a named SUBRANGE answer the base type's bounds

- **Type:** bug (silent wrong value) — **Track A**
- **Found:** 2026-08-09, an FPC differential over the ordinal surface.
- **Pre-existing.**

```pascal
type TDigit  = 0..9;
     TLetter = 'a'..'e';
WriteLn(Low(TDigit),  ' ', High(TDigit));    { FPC 0 9    pxx -2147483648 2147483647 }
WriteLn(Low(TLetter), ' ', High(TLetter));   { FPC a e    pxx #0 #255 }
```

Silent, and the shape that bites is the idiomatic one — `for i := Low(T) to
High(T)` over a named subrange iterates the entire Integer range instead of the
declared bounds, so a loop meant to run ten times runs four billion.

## Why this should be small

The bounds are ALREADY retained. `AliasIsSub` / `AliasSubLo` / `AliasSubHi` were
added to the alias table for `{$R+}` range checks
(feature-pascal-range-checks-r-plus), and `ParseTypeKind` hands them back
through `LastTypeIsSub` / `LastTypeSubLo` / `LastTypeSubHi` when it resolves the
alias. So the data is in place and `Low`/`High` simply do not consult it — they
answer from the resolved BASE kind.

Check both spellings while fixing: a named alias (`TDigit = 0..9`) and an
inline-declared variable (`var d: 0..9`), which are two paths into the same
concept and have diverged before — the `string[N]` capacity was exactly this
shape (bug-a-string-n-type-alias-loses-its-capacity), where the inline form
worked and the alias form did not.

## Gate

Both spellings, integer and char subranges, `Low`/`High` and a
`for i := Low(T) to High(T)` loop that must run the right number of times, all
diffed against FPC.

## 2026-08-09 — FIXED

Both resolvers learned it, because they are one concept in two functions:
`TryConstHighLowValue` (the constant evaluator, for `const`/array bounds) and
`TryFoldHighLowType` (the expression path). Each resolved an alias to
`AliasTk[]` — the BASE kind — and never looked at `AliasIsSub`. Fixing only one
would have left `const DLo = Low(TDigit)` and `WriteLn(Low(TDigit))` disagreeing
with each other, which is the sibling trap this repo keeps paying for.

Measured against FPC, all identical:

```
int  0 9          char a e          neg  -5 5
const 0 9         loop 10           cloop 5
base -2147483648 2147483647 0 255   bool FALSE TRUE
```

The `loop 10` row is the point: `for i := Low(TDigit) to High(TDigit)` used to
iterate the whole Integer range.

### Verified

`test/test_high_low_const_expr.pas` extended — subrange bounds folded in a
`const` declaration, read as expressions, integer/negative/char subranges, and
both `for` loops counting their iterations. Byte-identical to FPC.
The base-type rows (`Low(Integer)`, `High(Byte)`, `Boolean`) are asserted
unchanged in the same file.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.


## Log
- 2026-08-09 — resolved, commit 9f01b58e3.
