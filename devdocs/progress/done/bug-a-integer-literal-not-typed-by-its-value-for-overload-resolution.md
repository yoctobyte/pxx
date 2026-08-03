---
track: A
prio: 45
type: bug
summary: "An untyped integer literal always types as LongInt (or Int64 if it does not fit), so overload resolution picks a different candidate than FPC: hi($1234) gives 0|4660 where FPC gives 18|52. Values are no longer truncated (that half is fixed) — this is the remaining FPC-parity gap."
status: done
owner: claude-A@opus5
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

## Resolution 2026-08-03 (claude-A@opus5)

Neither option as written — a third one, which is option 1's ranking model
applied *only* where ranking happens, so it carries none of option 1's risk to
arithmetic promotion and none of option 2's parallel array through callers.

- `LiteralIntKind(v: Int64): TTypeKind` (`symtab.inc`) — FPC's smallest fitting
  type, signed candidate before unsigned at each width.
- `MatchCallDelphiProcAddr` (`parser.inc`) is the SINGLE entry into
  `MatchProcCall*` and already refills a side channel there (`MatchArgRec`), so
  the literal re-typing rides the same loop: an argument that is a bare
  `AN_INT_LIT` (and not a folded enum member) contributes its `LiteralIntKind`
  to a parallel `litTypes`.
- That probe runs as an **EXACT-only** match ahead of the real one, via a new
  `MatchExactOnly` global that makes `MatchProcCall` / `MatchProcCallInUnit`
  return -1 after their exact phase. A hit is unambiguously FPC's candidate; a
  miss costs one chain walk and changes nothing.

Exact-only is what makes the `5` row come out right without a scoring pass:
`5` is ShortInt, ShortInt does not widen into Byte, and FPC ranks it onto
LongInt for exactly that reason — which is what the fallback already does. The
rows that need the fix are the ones where the literal's own type *is* a
candidate (200/Byte, 40000/Word, `$1234`/SmallInt).

The literal's expression type is untouched, so promotion is unaffected
(`b + 0` stays LongInt).

### Verified against FPC, not against expectation

Both regression tests now produce output **identical to FPC's**, diffed against
a real `fpc` build of the same source:

```
p(5) p(200) p(40000) p(100000) p(5000000000)
  ->  longint / byte / word / longint / int64          (was longint x4 + int64)
hi($1234)|lo($1234) -> 18|52                           (was 0|4660)
swap($1234)         -> 13330                           (was 305397760)
```

`test/test_hilo_swap.pas` gains six literal rows (5, 200, `$1234`, 40000,
`$12345678`, `$1122334455667788`) covering every width; all 20 rows match FPC.
`test/test_overload_no_narrowing.pas` keeps its shape, with the middle two rows
now byte/word; its comment no longer describes the gap as open. Makefile
expectations updated for both.

Blast radius is small by construction: the probe only wins on an EXACT hit for
the literal's smallest type, i.e. only where someone declared an overload taking
precisely Byte/ShortInt/SmallInt/Word/Cardinal. A non-overloaded `Foo(b: Byte)`
called `Foo(200)` resolves to the same routine, just one phase earlier.

`tools/gate.sh quick` GREEN (self-host fixedpoint byte-identical, testmgr quick,
FPC seed canary). No `compiler/builtin/**` change, so no repin needed.

## Log
- 2026-08-03 — resolved, commit PENDING.
