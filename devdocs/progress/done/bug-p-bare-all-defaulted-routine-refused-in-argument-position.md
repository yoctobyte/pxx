---
track: P
prio: 40
type: bug
blocked-by: []
summary: "A bare all-defaulted routine name is refused in ARGUMENT position, though statement and expression position now fill the trailing defaults and call — and in the default (objfpc) mode the meaning is unambiguous, because a procedural reference requires `@F` there."
status: done
owner: agent-acpn
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

## 2026-08-16 — step 1 was already done; step 2 was a SILENT WRONG VALUE

### Step 1 does not exist any more

The ticket's own repro compiles and answers correctly, on HEAD **and on
`pinned`**: `Check('x', F, 6)` prints 6, and so do the nested, arithmetic,
comparison and method-receiver shapes. Default mode reaches the trailing-defaults
fill from argument position already — presumably carried in by
`3195e3947 fix(P): float literal defaults, and one parser for all four param
sites`. Verified against FPC 3.2.2 rather than assumed.

So the ticket's premise is stale, and what it called the *optional* half is
where the bug actually lives.

### Step 2, measured against FPC: two defects, one shape

Under delphi mode, where a bare name may also mean the address:

```pascal
Chk('x', F, 6);            { F(k: Integer = 3) }
```

pxx printed **4247470** — F's ADDRESS, into an Integer sink, silently. FPC
prints 6. `TryDelphiBareProcArg` took the address for any function *with
parameters*, and an all-defaulted function is paramless AT THE CALL SITE: it
belongs with the paramless ones, which parse as a call and reach `@F` only
through `MatchCallDelphiProcAddr`'s retry when the sink really is procedural.

Fixing that exposed the second, which is the more interesting one:

```pascal
C2(Apply(F, 5), 10);       { Apply(f2: TFn; v: Integer) }
```

**jumped to address 6** — F's RESULT, called as a function pointer — while the
identical `Apply(F, 5)` at statement level was fine. The retry's "did this land
on a procedural parameter" test read `SymProcSig` off the param SYMBOL, and
`Params[].SymIdx` does not outlive the callee's scope; in a program with enough
symbols to recycle it, the test answered "not procedural" and the spurious
numeric match stood. `ProcParamProcSig` is the parallel array that answers this
from a CALLER — its own comment in `defs.inc` says exactly that — and it is what
both the needAddr test and the rewrite now consult.

Note the shape: the bug needed a program big enough to recycle a symbol, which
is why every small repro passed. That is the same family as
[[project_symtab_alloc_parallel_array_landmine]] and the TSymbol-field landmine
— caller-visible facts belong in a parallel array, never on a scoped symbol.

### `ASTCallParenless`

A new AST parallel Boolean marks a call the parser built from a bare parenless
name whose arguments are all compiler-filled defaults. The @-optional retry
needs it to tell `F` from a written `F(2)`: the first may legitimately become
`@F` when the sink is procedural, the second may not — turning that into an
address silently would be the same class of bug this ticket is about.

### Tests

`test/test_delphi_bare_alldefaulted_arg.pas` — 8 rows, every one of them FPC
3.2.2's answer on the same source under `-Mdelphi`, including the nested shape
that needed the recycled symbol. `test/test_default_params_methods.pas` gains
the three ARGUMENT-position rows its own comment used to say were deliberately
untested (31 → 34), and that comment now records why the site stopped being
ambiguous.

### Gate

`make compiler/pascal26` (self-host fixedpoint, byte-identical) + `tools/gate.sh
quick` GREEN, FPC seed canary included.

## Log
- 2026-08-16 — resolved, commit c78227809.
