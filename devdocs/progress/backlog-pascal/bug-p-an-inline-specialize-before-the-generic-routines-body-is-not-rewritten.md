---
track: P
prio: 45
type: bug
blocked-by: []
status: open
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
