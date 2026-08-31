---
slug: bug-p-a-stray-end-at-unit-implementation-top-level-is-silently-skipped
track: P
prio: 45
type: bug
status: backlog
owner:
blocked-by: []
summary: "pasparser_proc.inc:5247 ends a unit only on `end` IMMEDIATELY followed by `.`; any other top-level `end` in the implementation section is consumed by a bare `else Next` and NOTHING is reported. A routine body that consumes one `end` too FEW is therefore invisible -- the spare is eaten and the unit compiles. The mirror (one too MANY) errors, but at EOF, because the loop then lands on the bare `.`. Same silent-skip shape that bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped measured at 1949 events and replaced in the arm NEXT DOOR, leaving this one. Found while localising the rung-6b wall in feature-pascal-corpus-expansion. NOT yet known to hide a live bug -- the cost of turning it into an error is unmeasured and that measurement is the first task, exactly as it was for the sibling."
---

# A stray `end` at unit-implementation top level is silently skipped

## The code

`compiler/pasparser_proc.inc:5247`:

```pascal
if CurTok.Kind = tkEnd then
begin
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
    doneImp := True
  else
    Next;            { <-- silent }
end
```

## Why it matters

A unit's implementation section has no legitimate top-level `end` other than
the terminator. So this arm only ever fires when a routine body finished in the
wrong place — and it fires **silently**, absorbing the evidence.

**The class is asymmetric, and that is the finding:**

| a body consumes | what happens |
| --- | --- |
| one `end` too **many** | loop lands on the bare `.`, `UnitSectionStrayToken` errors — **at EOF**, never at the defect |
| one `end` too **few** | the spare `end` is eaten here, **no diagnostic at all**, unit compiles |

So half of this bug class cannot be observed, and the observable half reports a
position that is a constant (the file's last line) rather than a coordinate.
Measured on `generics.collections.pas` across three truncations: 4165 lines →
error at 4165, 4161 → 4161, 2489 → 2489.

## Its sibling is the precedent, and the warning

[[bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped]] turned
the *general* stray-token skip in this same loop into an error. Its measurement
is the model and the caution: the skip path fired **1949 times** across `test/`
and `lib/rtl`, every event a piece of an `operator` declaration header, and
turning it into an error without first adding `SkipOperatorDeclHeader` would
have stopped every operator-declaring RTL unit from compiling. It notes that
*"the implementation loop's copy of this never fired at all"* — but that was the
**stray-token** arm, not this `tkEnd` arm, which nobody instrumented.

## First task is the measurement, not the fix

Instrument this `else Next` and compile `test/` and `lib/rtl`. If it never
fires, it becomes an error and the invisible half of the class becomes visible.
If it fires, each event is either a real latent body-length bug or a shape that
needs consuming as a unit — and which of those it is decides the whole ticket.

Found while localising the rung-6b wall in
[[feature-pascal-corpus-expansion]]. **Not yet known to hide a live bug**; the
wall being chased there is the *over*-consuming direction, which does error.
