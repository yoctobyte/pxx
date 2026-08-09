---
track: A
prio: 55
type: bug
blocked-by: []
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
