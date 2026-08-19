---
track: A
prio: 40
type: bug
blocked-by: []
summary: "AIntToStr(n) returns the EMPTY STRING for any n < 0 — `while n > 0` never enters. It is the compiler's own IntToStr, used in ~40 diagnostics across the Pascal, NilPy and C frontends and the C preprocessor, so a negative value silently drops out of an error message rather than being reported wrong-looking."
---

# AIntToStr returns '' for negative numbers

```pascal
function AIntToStr(n: Integer): AnsiString;
begin
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n > 0 do            { <-- n < 0 never enters }
    ...
```

`AIntToStr(0)` = `'0'`. `AIntToStr(-5)` = `''`. No minus sign, no digits, no error.

Found while moving the function out of `aparser.inc` into the new shared
`compiler/util.inc` ([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]).
Moved **verbatim**, defect included, so that the move stayed provably mechanical
and the self-host binary stayed byte-identical; fixing it is this ticket.

## Why it has survived

Every current caller passes a count, an index, a parameter number or a version —
quantities that are non-negative in practice. So the failure mode is not a wrong
number, it is a **diagnostic with a hole in it**: `'takes at most  arguments'`
rather than `'takes at most -1 arguments'`. A message missing a number reads as a
formatting slip, not as a value bug, which is precisely why nobody chased it.

That also makes it the cheap kind of latent bug to fix now rather than the day
something starts passing a negative sentinel: several call sites pass
`Procs[mpi].ParamCount - 1`, which is `-1` when `ParamCount` is 0.

## Fix

Handle the sign, then the magnitude. Watch `Low(Integer)`, whose negation
overflows — the usual guard is to build digits from the negative side, or to
special-case it.

Gate: the per-fix loop. Add a test covering `-1`, `0`, `Low(Integer)`, and one
ordinary negative.
