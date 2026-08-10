---
track: A
prio: 55
type: feature
blocked-by: []
---

# Own-language-first symbol resolution: the native language wins

**Decided by the user, 2026-08-10.** Re-filed from
`decide-own-language-first-name-resolution` (Track U) — the rule is settled, so
this is work, not a question.

> "yes, symbol resolution. same deal — if a symbol is defined in multiple
> languages, the _native_ language wins. that is cleanest."
>
> "no shame in double code. since, math.c and math.pas do not behave identical.
> there are more differences. the choice for 'oh, and C can just use pascal's
> math library' was a wrong one, in retrospect." — user

## The rule

**If a symbol is defined in more than one language, the call site's own language
wins.** A C call to `exp` binds C's `exp`; a Pascal call to `Exp` binds Pascal's
`Exp`. They are different functions and they are allowed to be — see below.

This is a hard precedence, not a tie-break, and it outranks import order.

## The retrospective that reframes this

The collisions were treated as a naming problem. They are a symptom of a design
error: **C was allowed to reach into Pascal's math unit.** `math.c` and
`math.pas` do not behave identically and were never going to — different
accuracy targets, different edge-case handling, different history. Sharing them
was the wrong call.

The house rule already covers it: duplicated helpers per frontend are FINE
(`devdocs/dev/` and the standing preference on shared-AST helpers). Two
implementations that differ is the correct outcome here, not technical debt.

## The payoff, and the acceptance test

`lib/crtl/src/math.c` is a COMPLETE C math library already — 114 functions on
correctly-rounded double-double kernels. Ten of them are deliberately misnamed
to dodge Pascal, with the reason in the source:

```c
/* NOT named `exp`: that name collides case-insensitively with Pascal Exp
   (two definitions -> silently broken call binding). C callers reach this
   through `#define exp(x) __crtl_exp(x)` in crtl math.h. */
double __crtl_exp(double x) { ... }
```

Affected: `__crtl_exp`, `__crtl_log2`, `__crtl_log10`, `__crtl_sin`,
`__crtl_cos`, `__crtl_tan`, `__crtl_sinh`, `__crtl_cosh`, `__crtl_tanh`,
`__crtl_hypot`.

**Acceptance: those ten go back to their real names and the `#define`s in crtl
`math.h` are deleted**, with C programs still binding the crtl implementations.
That is the visible proof the rule works. (That half is Track C file-ownership —
`lib/crtl` — so land the compiler rule under A first, then the cleanup.)

## The rule costs no capability — the override already exists

> "plus, programmers, if they insist, can do it anyways.. from pascal, just
> import 'math.c' and use _those_ functions. there is no conflict." — user

This is what makes the hard precedence safe to adopt. Own-language-first is the
DEFAULT, not a wall: a programmer who genuinely wants the other language's
implementation names the file explicitly and gets it.

Already supported today — `parser.inc:29759` recognises a `.c` / `.h` extension
in a quoted `uses` path and compiles that unit:

```pascal
uses './math.c';     { C's exp, not Pascal's Exp }
```

And there is no conflict to arbitrate in that case *because the programmer named
the unit*. The precedence rule exists to settle an ambiguity; an explicit path
removes the ambiguity rather than losing to it.

So the full design is: **implicit resolution prefers your own language; explicit
import overrides it.** Nothing becomes unreachable — it just has to be asked for
by name, which is the right shape for "I know these two differ and I want that
one".

Caveat for whoever writes the test: the explicit-path form has a known landmine
of its own — a `uses './x.c'` whose BASENAME collides with the enclosing unit's
name is silently dropped with no diagnostic
(`bug-c-uses-path-basename-collides-with-enclosing-unit-name`). Don't name the
fixture `math.pas`.

## Why the `__pxx_*` PAL entries are NOT a counter-example

The earlier U ticket worried that the rule would break the PAL: `__pxx_open`
and friends are declared in C headers and DEFINED in Pascal.

They are safe, because the rule fires only on a symbol *defined in more than one
language*. A PAL entry has ONE declaration visible to C and one Pascal
definition — a single symbol with two halves, not two competing definitions.
Nothing to arbitrate. Worth an explicit test so it stays that way.

## Fallback already measured

If full precedence turns out to be expensive, a narrower rule closes the whole
KNOWN collision class on its own: *a cross-language name match must agree on
case*. Every Pascal spelling is capitalised (`Exp`, `NaN`, `Log2`, `Log10`,
`Floor`, `Ceil`) and every C name lowercase; `pow`/`log` never collided at all
(`Power`/`LogN` are different names). Measured 2026-08-10 — details in the
superseded U ticket. Treat it as a safety net, not the goal: the user's rule is
the one to implement, and case-agreement does not express "the native language
wins".

## Not in scope

MODULE resolution — which FILE an import name loads — is a separate, already
largely-correct mechanism: the Pascal `uses` path builds `<name>.pas` candidates
only (parser.inc:29827+) and each frontend searches its own extension. Same
slogan, different machinery. Don't tangle them.

## Gate

C programs binding crtl's math with the ten names de-prefixed; a Pascal program
using `math` unaffected; a mixed program (C code plus a Pascal `uses math`) with
each side binding its own; the `__pxx_*` PAL entries still resolving; C tests
green + `make test` + self-host byte-identical.
