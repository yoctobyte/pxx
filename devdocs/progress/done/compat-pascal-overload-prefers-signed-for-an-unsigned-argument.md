---
slug: compat-pascal-overload-prefers-signed-for-an-unsigned-argument
track: A
prio: 12
status: done
owner: frankS
resolved-by: frankS
summary: "TITLE AND PRIO ARE BOTH WRONG AND THE FIX IS IN. pxx did not prefer signed -- it had NO signedness preference at all, and the winner was whichever arm was DECLARED FIRST: OverloadArgRank ties every machine-int pair at rank 1 and MatchProcCall's Phase 1c2 returns the first chain match. The table in the body was measured in ONE declaration order, which is why it reads as a property of the types and why its `Integer` row is recorded as agreeing with fpc; swap the two declarations and that row disagrees too. The other claim it was ranked 12 on -- `no value is wrong today` -- is also false: with `f(QWord)` declared first, `Big(v) = v > 1000000` called with an `Integer` -5 answers TRUE in pxx and FALSE in fpc, through the free path AND the method path. A silently wrong value in the shape a numeric library actually writes. Fixed unconditionally, which is what this ticket's own Scope section proposed: prefer a candidate whose integer parameters match the argument's SIGNEDNESS, falling through to exactly today's behaviour when none does -- a strict sub-pass ahead of Phase 1c2 on the free path, and a tie-break consulted only on equal rank in FindUMethOverloadAhead and FindUCtorOverloadArgs. ArgNarrowsInt untouched. Fixture test_a_an_integer_overload_pair_is_chosen_by_signedness declares every family in BOTH orders; 13 of its 16 rows flip against the pinned pre-fix compiler and 3 print a wrong value. Gate GREEN."
---

# Overload resolution picks the signed arm for an unsigned argument

With both arms visible, a `Cardinal` argument goes to `Int64`, where FPC sends
it to `QWord`:

```pascal
function Sig(v: Int64): AnsiString; overload;  begin Sig := 'i64';   end;
function Sig(v: QWord): AnsiString; overload;  begin Sig := 'qword'; end;
var c: Cardinal;
begin c := 5; WriteLn(Sig(c)); end.
```

| argument | pxx | fpc |
| --- | --- | --- |
| `QWord` | qword | qword |
| `Int64` | i64 | i64 |
| **`Cardinal`** | **i64** | **qword** |
| `Integer` | i64 | i64 |
| `q shl 1` (QWord expr) | qword | qword |

So only the *narrow unsigned* case differs: pxx ranks "widen to the signed 64-bit
arm" and FPC ranks "keep the signedness". Both conversions are lossless for a
Cardinal, so no value is wrong today — this is a preference, not a defect, and it
is filed as compat rather than as a bug for that reason.

## Why it is still worth recording

It becomes observable the moment the two overloads *behave* differently rather
than merely accepting different types — which is exactly the situation in
`bug-b-inttostr-of-a-qword-above-2-63-renders-negative`. Once
`IntToStr(QWord)` lands beside `IntToStr(Int64)`, a `Cardinal` argument will
still route to the Int64 arm here and to the QWord arm under FPC. For
`IntToStr` the rendered digits are identical either way, so nothing breaks; for
a user's own pair of overloads it could pick the other function.

## Scope

The rule to match is FPC's: among candidates reachable by widening, prefer one
that preserves signedness over one that does not. Narrow-signed→`Int64` and
narrow-unsigned→`QWord` both then fall out.

Belongs behind `--strict-overload` if it turns out to move any existing
resolution, and unconditionally if it does not — preferring the same-signedness
arm is the better default independently of FPC.

## Found by

An integer-arithmetic differential, while confirming that
`bug-b-inttostr-of-a-qword-above-2-63-renders-negative` was a missing overload
rather than a resolution failure. It is a resolution failure — just not that one.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 25e518dc9.


## CORRECTION (frankS, 2026-09-09) — the title names a preference the compiler does not have

Everything above this line is the ticket as filed and it stays for the record.
Two of its claims are false and they are the two it was ranked on.

**It is not a preference, it is the absence of one.** `OverloadArgRank` ties
every machine-integer pair at rank 1 (`if TypeIsMachineInt(pTk) and
TypeIsMachineInt(aTk) then Result := 1`), and `MatchProcCall`'s Phase 1c2
returned the FIRST candidate in chain order. So the answer was the
first-declared arm, and `Int64` happened to be declared first in the repro.

**The table above was measured in one declaration order.** Its `Integer` row
records pxx and fpc agreeing on `i64`. They agree only because of the order.
Swap the two declarations and pxx answers `qword` for an `Integer` argument
while fpc still answers `i64`. A confounder held fixed reads as a fact about
the subject and nothing in the table says it was there — which is how the
ticket concluded that "only the *narrow unsigned* case differs".

**"No value is wrong today" is false, and that is what priced it at 12.**

```pascal
function Big(v: QWord): Boolean; overload;  begin Big := v > 1000000; end;
function Big(v: Int64): Boolean; overload;  begin Big := v > 1000000; end;
var si: Integer;
begin si := -5; WriteLn(Big(si)); end.
```

pxx `TRUE`, fpc `FALSE`. The sign-losing arm was chosen over an exact-signedness
one sitting in the same overload set. An `Int64`/`QWord` pair is what a numeric
library writes and passing it an `Integer` is ordinary code, so this is not the
"programmer made a presumed error" class — the source means the signed arm and
says so by the argument's type.

### Measured — three doors, both orders

fpc 3.2.2, at `1180aa627`, binary `226c79e87aaa`. **fpc is stable across the
swap on every row; pxx followed the swap on every row.**

| door | selector |
| --- | --- |
| free call | `MatchProcCall` Phase 1c2 (`compiler/symtab.inc`) |
| method | `FindUMethOverloadAhead` → `OverloadArgRank` (`compiler/pasparser_call.inc`) |
| constructor | `FindUCtorOverloadArgs` → `OverloadArgRank` |

Against the PINNED pre-fix compiler the fixture's 16 rows show the two
declaration orders disagreeing on **13**, three of them printing `qword BIG`.

## The fix

The ticket's own **Scope** section had the rule right and predicted the
disposition right: *"unconditionally if it does not [move any existing
resolution] — preferring the same-signedness arm is the better default
independently of FPC."* It does not move any, gate GREEN, so unconditional.

- **Free path:** a third pass on Phase 1c2's loop, run FIRST, admitting only a
  candidate whose every integer parameter matches its argument's signedness.
  The two existing passes are untouched and run unchanged after it, so a set
  with no signedness-matched candidate behaves exactly as before.
- **Method and constructor paths:** `OverloadSignMiss`, summed per candidate and
  consulted ONLY when two candidates score identically. **Not a rank** — sinking
  a sign mismatch to rank 2 would tie it with "merely compatible" and
  reintroduce the six-row `Pointer`/procedural defect the `TypeIsMachineInt` arm
  closed. What it replaces is the tie-break that was already there, and that
  tie-break was declaration order.
- `ArgNarrowsInt` deliberately untouched: it ranks on the default path too, and
  the default dialect's widening is intended behaviour. Expressing signedness as
  narrowing would demote candidates that are the only ones present.

### What the fixture can and cannot see

The `expr`/`ecard`/`unry` rows **cannot fail this bug** — they read the same
before and after, because `cd + 0` is a signed expression however unsigned `cd`
is. They are there so the rule cannot be passed by matching the SPELLED type.
The `call` and `cast` rows are there for a third reason: the method probe parses
arguments SPECULATIVELY and the committed loop re-parses them, so a rule that
ranks on the probe's reading needs checking on shapes where the two readings
could differ (frank-coordinator raised this against frankH's `ad7c03b03`, where
exactly that divergence made a call MATCH on one reading and build another).
All four such shapes agree with fpc in both orders.

## What this is really an instance of

Two other tickets in this group say the compiler *prefers* something —
[[bug-p-two-array-parameters-at-one-bracket-slot-are-decided-by-declaration-order]]
and [[bug-p-a-shadowed-soft-intrinsic-is-closed-without-consulting-the-arguments]].
In all three the compiler makes no choice at all: it runs out of discriminating
power and the tie-break becomes visible. **Reading agency into the outcome
points the fix at changing a preference instead of adding discrimination**, and
it points the ranking at a disposal — this one sat at prio 12 for it.
