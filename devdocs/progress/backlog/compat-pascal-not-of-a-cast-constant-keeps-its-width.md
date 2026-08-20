---
track: P
prio: 10
type: compat
blocked-by: []
summary: "`not Byte(0)` folds to 255 in pxx and to -1 in FPC — FPC evaluates a constant `not` in the Int64 domain and drops the cast's width. pxx matches Delphi. Variables agree; only the constant-folded form differs."
status: backlog
---

# `not Byte(0)` is 255 here and -1 in FPC

- **Track P** (Pascal frontend: constant folding of `not`), tag **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe.

## What differs

```pascal
Writeln(not Byte(0));        { pxx 255          FPC -1 }
Writeln(not LongWord(0));    { pxx 4294967295   FPC -1 }
```

With a *variable* the two agree — `b: Byte = 0; Writeln(not b)` is 255 in both,
`not c` for a LongWord is 4294967295 in both. Only the folded constant form
diverges: FPC evaluates a constant `not` in its Int64 constant domain and the
cast's width does not survive.

## Which one is right

Delphi's answer is 255: `not` on a Byte yields a Byte. pxx agrees with Delphi,
FPC does not. So this is recorded rather than "fixed" — changing it would move
us away from Delphi to match an FPC constant-folding artifact.

## Where it could bite

`const MASK = not Byte(0);` then `x and MASK` — 255 versus -1 masks a different
number of bits. That is the one shape worth grepping for if a real FPC program
ever disagrees with pxx on a mask.
