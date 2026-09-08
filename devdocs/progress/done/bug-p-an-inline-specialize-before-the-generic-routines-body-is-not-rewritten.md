---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankS
---

# An inline `specialize` used before the generic routine's BODY is not rewritten

```pascal
unit uinl2; {$mode objfpc}{$H+}
interface
generic function TestFunc<T>(aTest: T): T;      { declared here }
procedure Run;
implementation
procedure Run;
begin
  Writeln(specialize TestFunc<LongInt>(42));    { used here -- pxx refuses }
end;
generic function TestFunc<T>(aTest: T): T;      { body only here }
begin Result := aTest; end;
end.
```

`undefined variable (specialize)`; fpc 3.2.2 prints 42. This is the live wall
of `tgeneric102.pp` — measured, not read off its skip row.

## The boundary, which is NOT "expression position"

An inline `specialize` in expression position works: assigned, nested in a call
argument, and qualifying a generic CLASS (`specialize TTest<String>.Test('x')`
on line 35 of ugeneric102 parses fine — the first error is line 41, the ROUTINE
form). And the same use before the body in a **program** is refused by fpc too:

    program p; procedure Run; begin Writeln(specialize Twice<LongInt>(21)); end;
    generic function Twice<T>(a: T): T; ...     { fpc: Identifier not found }

So the rule both compilers implement is DECLARATION before use, and the unit
case is the one where pxx and fpc part: the interface header makes the name
visible and pxx still refuses.

## Cause

`SpecializeInlineGenericFuncUses` starts its rewrite sweep at `i := TokPos` —
immediately after the generic routine's DEFINITION. Its declaration-arity
pre-pass already walks the whole stream (`i := 0`), so the machinery to find an
earlier declaration is present; only the rewrite is forward-only.

## Why the one-line fix is wrong, and this is the part to keep

Starting the sweep at the routine's earliest declaration means the rewrite
edits tokens BEHIND `TokPos` — and the sweep is destructive, collapsing
`specialize F<T>(` to `F_T(` via `RemoveTokens`. The file already warns about
exactly this shape:

> AdjustPass2Spans is a no-op outside the body pass, so a removal BEHIND TokPos
> would silently invalidate TokPos and every DeclItem span already recorded.

This runs in pass 1, so the casualties would be `TokPos` itself and the pass-1
`DeclItem` spans — the same family as the pass-2 defect fixed at `2f1fe06b9`,
one pass over. So the fix is: adjust `TokPos` and the recorded spans on a
behind-cursor edit (the pass-1 twin of `AdjustPass2Spans`), THEN move the sweep
start. Doing the second without the first trades a refusal for a desync, which
is the worse direction — a refusal has a complainant.

`sweepEnd`'s sibling-overload bound (`2f1fe06b9`'s neighbour, tgenfunc8) is
unaffected: uses before a sibling's declaration already belong to this template
alone, and a `sweepStart` at this routine's own declaration is the symmetric
bound at the other end.

## Not covered by this

`tgeneric107.pp` (`specialize G<Integer>.F := @specialize G<Integer>.Create.Foo`)
fails differently — `@G$Integer.Create: unknown method` — and `tgenfunc10.pp`
fails at `unknown type: TTest`. Both were measured at the same binary and
neither is this cause; do not fold them in on the strength of the shared word
"inline".

## FIXED 2026-09-08 at compiler `1defef6b62d0` — and the ticket's own prescription is what landed

`SpecializeInlineGenericFuncUses` now starts its rewrite sweep at `sweepStart`,
the EARLIEST declaration of this name at this arity, instead of at `TokPos`. The
arity pre-pass already walked the whole stream to build `declArity`, so finding
that index cost one comparison inside a loop that was already there.

**And the guard the ticket said must land first, landed first.** `AdjustPreScanSpans`
is the pass-1 twin of `AdjustPass2Spans`: on a behind-cursor collapse it moves
`TokPos` and every already-recorded `DeclItem` span. Without it the sweep would
have traded a refusal for a desync, which is the worse direction because a
refusal has a complainant — this ticket's own words, and they were right.

It is called EXPLICITLY from the one site rather than wired into
`RemoveTokens`/`InsertTokens` like its twin. Those two have dozens of callers
that edit AHEAD of the cursor, where nothing needs adjusting, and several already
compensate by hand from the count they get back; wiring it in would double the
correction at every one of them. That asymmetry is written at the function.

### The boundary, re-measured — the scope rule is intact

|  | pxx | fpc 3.2.2 |
| --- | --- | --- |
| interface header, use, then body (the repro) | **42** | 42 |
| header, body, then use (always worked) | 42 | 42 |
| no header at all, use, then body | **refused** | refused |

The third row is the one that must NOT change and it did not: with no
declaration ahead of the use, both compilers refuse. `sweepStart` defaults to
`TokPos`, so in a PROGRAM — where a generic routine has no separate header —
nothing moves at all. **A unit is the only place a declaration and its body can
be apart, which is exactly why this construct has no program-level spelling and
why the divergence was unit-only.**

### `tgeneric102.pp` BURNS

It compiles, runs `rc=0`, and its output matches the fpc 3.2.2 oracle line for
line (diffed, not eyeballed). Its skip row is removed: **49 gap rows -> 48.**

### Fixture

`test/test_an_inline_specialize_above_the_generic_routines_body.pas`
(`test_inlspecfwd26`) with `test/units/uinlinespecfwd.pas`, differential against
fpc 3.2.2. Two rows print 42 and 32 rather than one number twice: both uses
specialize ONE template at ONE type, so a sweep that collapsed them, or a body
emitted once under a shared mangled name, would print the same value in both.
The third row — the must-still-refuse one — is stated in the file's header
rather than asserted, because a compile error cannot be a row of an output
comparison, and "not asserted" would otherwise read as "not checked". Positive
control on pin v407: `undefined variable (specialize)` at the unit's line 18.

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
