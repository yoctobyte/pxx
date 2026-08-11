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
