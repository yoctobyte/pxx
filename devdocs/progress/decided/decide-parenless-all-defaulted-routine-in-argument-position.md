---
summary: "Bare `F` in ARGUMENT position where F is a routine with all-defaulted parameters: call it, or take it as a procedural reference? Statement and expression positions now call it; argument position is genuinely ambiguous and was deliberately left unfixed."
type: decide
track: U
prio: 40
found-by: claude-AN
---

# Bare all-defaulted routine in argument position — call or reference?

Escalated rather than guessed while fixing
[[bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable]].

## The fork

That fix made a bare name reach the trailing-defaults fill in two positions:

```pascal
procedure P(k: Integer = 3);
function  F(k: Integer = 3): Integer;

P;                 { statement  — now calls P with k=3 }
a := F;            { expression — now calls F with k=3 }
Check('x', F, 6);  { ARGUMENT   — still refused }
```

Argument position was left alone **on purpose**: unlike the other two, it has a
second legitimate reading. `F` there could be

1. **a call** — `Check('x', F, 6)` passes `F`'s result, which is what FPC does
   when the parameter is `Integer` and is what the other two positions now do; or
2. **a procedural reference** — if the parameter's type is `function: Integer`,
   the name must denote the ROUTINE, not its result. PXX already resolves bare
   routine names this way for procedural-typed parameters.

So the answer depends on the PARAMETER's type, and the two readings are both
reachable for the same source text.

## Options

- **A — resolve by parameter type** (recommended). If the parameter is
  procedural and compatible, take the reference; otherwise fill the defaults and
  call. This is what FPC effectively does and keeps both existing behaviours.
  Cost: the decision needs the parameter type at the point the bare name is
  parsed, which is the same information overload resolution already has, but
  this path currently runs before it.
- **B — leave argument position refused.** `F()` is one character and
  unambiguous. Costs nothing, keeps the asymmetry: `a := F` works but
  `g(F)` does not, which will read as a bug to the next person.
- **C — always call in argument position**, requiring `@F` for the reference.
  Simplest rule, but it is a breaking change for any code passing a bare
  all-defaulted routine to a procedural parameter today.

## Recommendation

**A**, with **B** as the honest interim (which is where it stands now). The
asymmetry in B is a real wart but it is a *refusal*, not a wrong answer, so it
is safe to sit on. C should not be chosen without a survey of existing
procedural-parameter call sites.

## Notes

Whichever is chosen, `test/test_default_params_methods.pas` already carries a
comment saying argument position is deliberately untested, and the
expression-position cases there assign to a local first for exactly this
reason — update both when this is settled.

---

# NOT A DECISION 2026-08-11 (user) — the policy already exists and already answers it

> "FPC and delphi behave slightly different. we follow the mode flag. and follow
> FPC on it." — user

This never needed escalating. The general rule was settled long ago, is written
down, and is implemented: **PXX follows FPC/objfpc; Delphi behaviour appears
only under `{$MODE DELPHI}`.** `defs.inc:1448` states it as the flag's whole
purpose:

> `DelphiMode` — *"{$mode delphi}: relaxes a bare function name bound to a
> procedural-value target to take its address (@F-optional). PXX's dialect is
> otherwise one objfpc-ish superset; this is the one behavioural delta. Default
> off."*

and `ir.inc:2110` restates it for the sibling auto-call question: *"FPC/OBJFPC
never auto-call, and pxx must not either — this project targets FPC, with Delphi
behaviour only under {$MODE DELPHI}."*

## What that does to the fork

The fork assumed `F` in argument position is genuinely ambiguous. **It is not —
the mode decides which reading is even legal:**

| mode | can a bare `F` denote the ROUTINE? | so `Check('x', F, 6)` means |
| --- | --- | --- |
| default / objfpc (`DelphiMode` off) | **no** — a reference requires `@F` | unambiguously a CALL: fill the trailing defaults |
| `{$MODE DELPHI}` | yes, when the sink is procedural | resolve by parameter type — option **A**, already built |

So the ticket's options map onto the existing policy rather than competing with
it: **C in default mode, A under `{$MODE DELPHI}`** — and A's delphi half is
already implemented (`parser.inc:22179`, the sink-driven `AN_PROCADDR` arm,
guarded on `DelphiMode` and on the target carrying a proc signature).

**Option C's stated cost does not exist in default mode.** The objection was
that always-calling *"is a breaking change for any code passing a bare
all-defaulted routine to a procedural parameter today"* — but in objfpc such
code never compiled: it requires `@F`. The breakage would only be real in
`{$MODE DELPHI}`, which is exactly the mode where the rule is not "always call".

**Option B (leave it refused) is therefore wrong**, not merely a wart. It was
defended as *"a refusal, not a wrong answer, so it is safe to sit on"* — safe,
yes, but it refuses a construct the dialect's own rule says is legal and
unambiguous.

## Why it was filed at all

Not a resurfacing — filed **once**, fresh, in `7f7d3308e` ("file two findings
held back from the last stretch") by `claude-AN` while fixing
[[bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable]].
The escalation was made in good faith by CLAUDE.md's *escalate, don't guess*
rule, but the prior art was not checked: `DelphiMode` and its one-line policy
statement in `defs.inc` answer the question outright.

**Worth carrying:** *escalate, don't guess* is not *escalate instead of
looking*. Before filing a `decide-`, grep for an existing flag or policy —
a dialect question this project has already answered usually has a named
`Strict*`/mode boolean in `defs.inc` with the rationale in its comment.

## What is genuinely left — and it is a bug, not a decision

The trailing-defaults fill reaches statement and expression position but not
argument position, so in the DEFAULT mode — where the meaning is unambiguous —
`Check('x', F, 6)` is still refused. That is a plain Track P gap.

Re-filed as [[bug-p-bare-all-defaulted-routine-refused-in-argument-position]].
