---
track: A
prio: 45
type: bug
summary: "An untyped integer literal always types as LongInt (or Int64 if it does not fit), so overload resolution picks a different candidate than FPC: hi($1234) gives 0|4660 where FPC gives 18|52. Values are no longer truncated (that half is fixed) — this is the remaining FPC-parity gap."
---

# An integer literal is not typed by its VALUE for overload resolution

- **Type:** bug (FPC parity; no longer a wrong value, just a wrong candidate)
  — **Track A** (overload resolution / literal typing, `symtab.inc` +
  the frontend's constant typing)
- **Opened:** 2026-08-02, splitting the residual off
  [[bug-pascal-hi-lo-always-split-a-32-bit-value-regardless-of-argument-type]]

## What FPC does

An integer constant takes the **smallest type that holds it**, and overload
resolution then ranks candidates against that type:

| literal | FPC's type | picks, given p(Byte)/p(Word)/p(LongInt)/p(Int64) |
| --- | --- | --- |
| `5` | ShortInt | `longint` (no ShortInt candidate; widening is cheapest) |
| `200` | Byte | `byte` |
| `40000` | Word | `word` |
| `100000` | LongInt | `longint` |
| `5000000000` | Int64 | `int64` |

pxx types every literal that fits in 32 bits as LongInt (wider ones as Int64),
so it answers `longint` for the middle three.

## Why it matters — the visible symptom

`Hi`/`Lo`/`Swap` dispatch on the argument's type, so a literal argument gets
32-bit halves where FPC gives 16-bit ones:

```pascal
writeln(hi($1234), '|', lo($1234));   { FPC 18|52    pxx 0|4660 }
writeln(swap($1234));                 { FPC 13330    pxx 305397760 }
```

A cast works around it (`hi(Word($1234))` = 18|52 on both), and every *typed*
argument now agrees with FPC — this is literals only.

## What is already fixed (do not re-file it)

The dangerous half of this landed 2026-08-02: resolution used to take the first
COMPATIBLE candidate in chain order, so `p(40000)` with a `p(Byte)` overload
declared first printed **64** — the argument was silently truncated. `Phase 1d`
in `MatchProcCall` now prefers a candidate that does not narrow an integer
argument (`ArgNarrowsInt`), so the value always survives; only the choice among
lossless candidates still differs from FPC. Regression test:
`test/test_overload_no_narrowing.pas`.

## Approach

`MatchProcCall` receives `argTypes: array of TTypeKind` — kinds only, no
constant values — so the fix is not local to it. Two options:

1. **Type the literal at the front end** (FPC's actual model): give an integer
   constant the smallest fitting kind at the point it becomes an argument, and
   let the existing exact-match phase do the rest. Closest to FPC, and fixes
   every overload set at once — but it changes the type of every integer
   literal everywhere, so arithmetic promotion has to stay unaffected
   (`b + 0` must still be LongInt, as it is in FPC).
2. **Pass the constant value into resolution** alongside the kind, and let
   Phase 1d prefer the narrowest parameter that can hold it. Contained, but adds
   a parallel array through the resolver's callers.

Option 1 is the honest one; option 2 is what to do if 1 turns out to disturb
promotion. Either way the ranking rule to match is "smallest fitting type, then
cheapest widening".

## Acceptance

- The table above reproduces exactly, via `test/test_overload_no_narrowing.pas`
  extended with the FPC-measured expectations.
- `hi($1234)` = `18|52`, `swap($1234)` = `13330`, and
  `test/test_hilo_swap.pas` gains literal rows.
- Self-host fixedpoint + `make test`; a repin only if `compiler/builtin/**`
  changes again.
