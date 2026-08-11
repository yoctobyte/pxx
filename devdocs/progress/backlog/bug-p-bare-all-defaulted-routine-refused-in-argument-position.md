---
track: P
prio: 40
type: bug
blocked-by: []
summary: "A bare all-defaulted routine name is refused in ARGUMENT position, though statement and expression position now fill the trailing defaults and call — and in the default (objfpc) mode the meaning is unambiguous, because a procedural reference requires `@F` there."
---

# Bare all-defaulted routine name is refused in argument position

```pascal
procedure P(k: Integer = 3);
function  F(k: Integer = 3): Integer;

P;                 { statement  — calls P with k=3   OK }
a := F;            { expression — calls F with k=3   OK }
Check('x', F, 6);  { ARGUMENT   — REFUSED            bug }
```

Filed from [[decide-parenless-all-defaulted-routine-in-argument-position]],
which was closed as not-a-decision: the dialect rule that settles it already
exists.

## Why this is unambiguous, and therefore a bug

Argument position was originally left alone because `F` there has a second
legitimate reading — a procedural reference rather than a call. **The mode flag
decides which reading is legal, so there is no ambiguity to resolve:**

| mode | can a bare `F` denote the ROUTINE? | `Check('x', F, 6)` |
| --- | --- | --- |
| default / objfpc (`DelphiMode` off) | **no** — a reference requires `@F` | a CALL: fill the trailing defaults |
| `{$MODE DELPHI}` | yes, when the sink is procedural | resolve by the PARAMETER's type |

`defs.inc:1448` states the policy on `DelphiMode` itself: *"relaxes a bare
function name bound to a procedural-value target to take its address
(@F-optional). PXX's dialect is otherwise one objfpc-ish superset; this is the
one behavioural delta. Default off."*

## The work

1. **Default mode** — reach the trailing-defaults fill from argument position,
   the way statement and expression position already do. No parameter-type
   inspection is needed here: a bare name cannot mean the address in objfpc.
2. **`{$MODE DELPHI}`** — resolve by the parameter's type: procedural and
   compatible → take the reference, otherwise fill and call. The sink-driven
   arm this mirrors already exists for assignment context at
   `parser.inc:22179` (`AN_PROCADDR`, guarded on `DelphiMode` and on the target
   carrying a proc signature); the argument-position equivalent needs the
   parameter type at the point the bare name is parsed, which is information
   overload resolution already has but this path currently runs before.

Step 1 is the whole user-visible bug and is independently useful; step 2 is the
delphi-mode half and can follow.

## Tests to update

`test/test_default_params_methods.pas` carries a comment saying argument
position is deliberately untested, and its expression-position cases assign to a
local first for exactly this reason. Both should be updated when this lands, and
a `{$MODE DELPHI}` case added for step 2.

## Gate

Per-fix loop: `make compiler/pascal26` (the fixedpoint), the repro above, then
`tools/gate.sh quick`. Shared `parser.inc` — Track P's file today — so obey the
no-concurrent-edit-with-A rule.
