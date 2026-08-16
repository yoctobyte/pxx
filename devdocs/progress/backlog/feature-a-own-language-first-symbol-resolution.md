---
track: A
prio: 55
type: feature
blocked-by: []
status: backlog
owner: agent-an
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

---

## 2026-08-14 — MEASURED FIRST. The direction everyone assumed is closed; the opposite one is broken.

No code changed yet. Measuring before building, because this ticket's whole
framing — and its acceptance test — turn out to describe a direction that no
longer collides, while the direction nobody tested is silently wrong.

### C -> Pascal: CLOSED. The ten `__crtl_*` workarounds look VESTIGIAL.

The Pascal RTL is **not in scope for an ordinary C program at all** any more,
because `pxxcio.pas` no longer does `uses math` (verified: it is
`uses platform, builtinheap`). Two probes:

```c
extern double Power(double b, double e);   /* lives ONLY in lib/rtl/math.pas */
extern double Exp(double x);
```
```
pascal26: warning: crtl does not define Power — this C program will import them
          from the system C library at run time
```

Neither resolves to the Pascal routine. So there is nothing for a C name to
collide WITH.

And directly: a C body named `exp`, with no `<math.h>` macro in the way — i.e.
exactly what un-prefixing `__crtl_exp` produces — binds itself. **All ten
spellings do**, measured one program each:

| `exp` | `log2` | `log10` | `sin` | `cos` | `tan` | `sinh` | `cosh` | `tanh` | `hypot` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 42.0 | 42.0 | 42.0 | 42.0 | 42.0 | 42.0 | 42.0 | 42.0 | 42.0 | 42.0 |

(each defined as `double NAME(double x) { return 42.0; }` and called; 42.0 = the
C body won.)

**So this ticket's acceptance test may cost no compiler change at all.** That is
worth its own cheap experiment BEFORE the resolution work: de-prefix the ten in
`lib/crtl/src/math.c`, delete the `#define`s in crtl's `math.h`, run the C
corpus. If it is green, the workaround was already dead and can be deleted
independently of the rule. (Track C file-ownership — `lib/crtl` — so that half is
a C ticket, not this one.)

Note the doc `devdocs/dev/c-linking-and-crtl-autopull.md` still says math.c's
`sqrt`/`sin`/`pow` are "a thin bridge to the Pascal RTL". **Stale** — they have
real double-double C bodies now (`math.c:959` etc.). Fix that line when this
lands.

### Pascal -> C: BROKEN, order-independent, in the DOCUMENTED override path

This is the direction the ticket calls the safe escape hatch — *"programmers, if
they insist, can do it anyway... there is no conflict"*. There is a conflict, and
Pascal loses its own name:

```pascal
{ cm.c:  double exp(double x) { return 42.0; } }
program pm; uses math, './cm.c';
begin WriteLn('Exp(1.0) = ', Exp(1.0):0:4); end.
```

| program | result | correct? |
| --- | --- | --- |
| `uses math` alone | `2.7183` | yes — control |
| `uses './cm.c'` alone, calling `exp` | `42.0` | yes — the override works |
| `uses math, './cm.c'` | **`42.0`** | **NO** — wants `2.7183` |
| `uses './cm.c', math` | **`42.0`** | **NO** — same |

Pascal's `Exp` is silently hijacked by an imported C `exp`, case-insensitively.
Exactly the original `bug-c-pascal-math-names-hijack-libc-through-pxxcio`
mirrored — and this time it fires through the mechanism this ticket nominates as
the *solution's* safety valve.

**Order-independent, so this is NOT the scope-hiding rule.** Hiding makes the
last unit named win; both orders give C. The likely mechanism is that `Exp` is a
BUILTIN and builtins are deliberately demoted below any used unit (`demote` in
`MatchElig`), so a real C unit outranks it whatever the clause order. Verify that
before fixing — it means own-language-first has to outrank the builtin demotion
too, not just import order, which is a wider claim than the ticket makes.

### What this changes about the work

1. The **payoff moves.** De-prefixing the ten names is (probably) already
   available and is not what the rule buys. What the rule buys is that a mixed
   Pascal+C program keeps its own `Exp`.
2. The **rule must outrank builtin demotion**, not merely import order.
3. **No language tag exists to implement it with.** `ProcCdecl` is used as a
   proxy for "is a C proc" in `cparser.inc` — but it is documented as a CALLING
   CONVENTION flag, and a Pascal routine may be declared `cdecl`, so it is the
   wrong instrument (see the standing rule that convention decorators are
   decoration). This needs a real parallel array — `ProcLang` — set at proc
   registration from the frontend that is parsing, NOT derived from `ProcCdecl`.
   Parallel array, not a `Procs` field: a new field in the proc/symbol record
   breaks the self-host bootstrap.
4. `MatchElig` is still the right hook — it is where the hiding rule already does
   candidate removal, and own-language-first is the same shape (remove
   cross-language candidates when an own-language one exists). Third instance of
   one mechanism, after `demote` and `userOnly`.

### Gate note

Per `bug-p-uses-order-does-not-decide-which-unit-wins`, resolution changes have
twice passed `gate.sh quick` while broken — `make test-core` caught one and the
NilPy suite the other. This repo's standing rule is quick + self-host and let
Track T sweep, so land in small pushed steps and **watch `tools/twatch.py
--follow`** rather than widening locally; the C corpus and NilPy are exactly what
T's limited/full tiers cover.

### CORRECTION, same session — it is NOT builtin demotion, and the current behaviour matches FPC

The entry above says the mechanism is "likely" builtin demotion and to verify
before fixing. Verified. It is more subtle than that, and the correction changes
what this ticket should build.

**The discriminator.** Define a C body returning 42.0 for each name, `uses math,
'./x.c'`, call the Pascal spelling:

| Pascal name | a Pascal intrinsic? | result |
| --- | --- | --- |
| `Exp` `Sqrt` `Sin` `Cos` `Ln` `ArcTan` | yes | **42.0 — the C body wins** |
| `Power` | no | 1024.0 — Pascal wins |

Exactly the six names `parser.inc`'s auto-pull list treats as intrinsics lose,
and the one non-intrinsic does not. So a used unit's routine is shadowing the
INTRINSIC, not out-ranking `math.pas`.

**And that shadowing is CORRECT.** The control everyone skipped — do it with a
*Pascal* unit instead of a C file:

```pascal
unit pexp; function Exp(x: Double): Double;   { returns 42.0 }
program ctl2; uses math, pexp;  WriteLn(Exp(1.0));
```

| | result |
| --- | --- |
| pxx | `42.0000` |
| **FPC** | **`42.0000`** |

FPC does the same thing. A unit's routine shadowing a built-in is ordinary,
correct Pascal, and pxx already matches the reference implementation here.

**So the C case is that same correct mechanism, reached by a different door.**
`uses './cm.c'` imports the C file AS A UNIT, and its `exp` shadows the intrinsic
`Exp` case-insensitively, exactly as `pexp`'s would. There is no separate
cross-language defect to fix underneath it.

### Which turns this ticket into a genuine design fork

The ticket's safety argument is that explicit import is a clean override —
*"programmers, if they insist, can do it anyway... there is no conflict"*. The
measurement says otherwise, and the reason is structural:

> **Pascal is case-insensitive, so a Pascal program cannot SPELL the difference
> between its own `Exp` and an imported C `exp`.**

Importing `./math.c` therefore does not ADD `exp` alongside `Exp` — it REPLACES
it. "Ask for it by name" has no distinct name to ask with. That is not a bug in
the resolver; it is a property of the language pair, and it means
own-language-first cannot be both "a hard precedence" and "overridable by
explicit import" in Pascal. One of the two has to give:

- **Hard precedence wins:** `Exp` is always Pascal's, and an imported C `exp`
  becomes UNREACHABLE from Pascal by ordinary call — the override the ticket
  promises does not exist. Needs a spelling (qualified `cm.exp(...)`?) to stay
  honest.
- **Explicit import wins:** today's behaviour, consistent with FPC's
  unit-shadows-builtin rule, and the hazard stays — but only for a file the
  programmer explicitly named, which is a much smaller blast radius than the
  original `pxxcio` bug (that one hit EVERY C program with no opt-in at all).

Escalated as [[decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language]]
rather than guessed. **No code written** — implementing to the wrong horn here
would either break the documented override or leave the rule toothless.

### What is NOT in doubt

- The C -> Pascal direction is closed (first section above), so the ten
  `__crtl_*` prefixes are still probably deletable — `task-c-retire-the-crtl-name-dodge-prefixes`,
  independent of this fork.
- If the rule is built, it still needs a real `ProcLang` parallel array;
  `ProcCdecl` remains the wrong instrument.

## 2026-08-16 (Track U) — the missing spelling EXISTS: `uses '...' as cm`

The fork above says hard precedence "needs a spelling (qualified `cm.exp(...)`?)
to stay honest", and treats its absence as the reason the option cannot be
taken. **That spelling is real and shipped 2026-06-30**
([[feature-uses-alias-as]]). Verified on pinned:

```pascal
uses './mymath.c' as cmath;
WriteLn(Cube(3));        { 27   — Pascal's }
WriteLn(cmath.cube(3));  { 1027 — C's      }
```

So both arms of the fork are now live, and the argument that decided it changes:
**hard precedence no longer makes an imported C symbol unreachable.** It makes
it reachable only by name, which is the ticket's own stated intent ("nothing
becomes unreachable, it just has to be asked for by name").

This does not re-decide anything by itself — `decide-own-language-first-...`
already picked its direction and that call is the owner's. It removes the one
factual obstacle that was recorded against the other arm, and the acceptance
test named here (the ten `__crtl_*` `#define`s going back to their real
spellings) now has a working escape for the collision it deliberately creates.

Full reasoning, the four measured forms, and the deliberate decision that bare
`uses './x.c'` stays unbound: [[decide-cross-language-qualifier-syntax]].


## 2026-08-16 — UNBLOCKED (board maintenance, no code)

`decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language`
was **decided on 2026-08-14** (`e0bdf1499`) — a rule SET, not one rule:
own-language-first as the principle, case must agree for a cross-language match,
compiler warnings on top, and "a programmer who insists on both math.pas and
math.c faces the consequences".

This ticket kept the answered `blocked-by:` in its frontmatter AND sat in
`unfinished/`, so it was hidden from `ready`/`next` twice over — the two
independent switches described in [[project_parked_tickets_are_invisible_two_independent_ways]].
Both cleared: `blocked-by: []`, moved to `backlog/`.

Nothing is half-applied — the 2026-08-14 entry above says "No code changed yet",
so this is a clean start, not a resume. The measurement in that entry stands and
narrows the work: the C -> Pascal direction is already closed (nothing for a C
name to collide with), so what remains is the Pascal -> C direction plus the
cheap `lib/crtl` de-prefix experiment, which is Track C's file-ownership.
