---
slug: bug-p-a-stray-end-at-unit-implementation-top-level-is-silently-skipped
track: P
prio: 45
type: bug
status: done
owner: frankD
blocked-by: []
summary: "FIXED 2026-09-04. The `else Next` at pasparser_proc.inc's implementation-loop tkEnd arm is now an error naming the unit, so a routine body one `end` SHORT is reported at the spare `end` instead of compiling clean. The measurement the ticket asked for first: ZERO events across 2571 corpus sources under the new PXXDBG=p.strayend -- and the probe is proven live rather than merely quiet, which a zero census needs before it means anything (a unit with a spare top-level `end` reports one event, and built silently with no diagnostic before this). The over-consuming mirror still errors at EOF via UnitSectionStrayToken; that half is unchanged and its position complaint is left as the separate finding it is."
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


## Resolution 2026-09-04 (frankD, Track P)

**The census first, exactly as the ticket ordered it — and its sibling is why
that order is not ceremony.** `bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped`
turned the *stray-token* arm of this same loop into an error, and its skip path
fired **1949 times**, every event a piece of an `operator` declaration header.
Erroring first there would have stopped every operator-declaring RTL unit from
compiling.

This arm is the opposite: **0 events across 2571 corpus sources** under the new
`PXXDBG=p.strayend`, which reports the swallow instead of erroring.

**A zero census is worth nothing until the probe is proven live**, because a
probe wired to an unreachable arm produces the same zero. Positive control — a
unit with a spare top-level `end`:

- probe on: `PXXDBG p.strayend SWALLOWED end at=ustray2:9 unit=ustray2`, one event
- **pinned compiler: `ok:`, and the program runs and prints its output** — no
  diagnostic at all

So the arm is reachable, it was silently accepting malformed units, and nothing
legitimate in the corpus reaches it. That is the whole decision the ticket
deferred.

## The diagnostic

It names the **unit** and says what is actually wrong, rather than reusing
`UnitSectionStrayToken`'s "it starts no declaration (a mistyped section
header?)" — which is true of the *other* half of this class and misleading for
this one:

```
error: unexpected `end` at the top level of unit unit_stray_end's implementation
section: a routine body above it is short one `end`, and only `end.` ends the unit
```

The over-consuming mirror is untouched: it still lands on the bare `.` and
reports through `UnitSectionStrayToken` **at EOF**, i.e. at a position that is a
constant rather than a coordinate. Making it report at the defect needs a
brace-depth memory the loop does not keep, and is not attempted here.

## Coverage — and the half that actually matters

The refusal case asserts both that it is refused and that the message names its
unit. **But the row that earns its place is the other one.** "A stray `end` is
now an error" is unfalsifiable in the direction that actually breaks people — an
over-eager arm rejecting ordinary source — unless something asserts the ordinary
shapes still compile. So there is a zero-diagnostic fixture covering every
legitimate `end` an implementation section can present: statement `end`s, a
`case` `end`, block arms of an `if`/`else`, a method body, `try`/`finally`,
`initialization`/`finalization`, and the classic `begin ... end.` unit-init form
whose closing `end.` doubles as the terminator. Two units, because one unit
cannot carry both init forms. It asserts **values**, not merely that it
compiled, so a future arm that swallows a real `end` again cannot pass it by
accident.

Both are controlled against the pin: the fixture is clean there too, and the
failure case is built silently by it.

Credit for the shape of the zero-count fixture: frankS, from four
directive-classification tickets the same day — *"my test asserts the TOTAL
warning count, not just that the bad cases warn ... `exactly 5` is the only row
that catches an inert one starting to warn."*

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 5981ed071.
