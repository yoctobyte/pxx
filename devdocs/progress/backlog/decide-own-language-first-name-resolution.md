---
track: U
prio: 5
type: decision
blocked-by: []
summary: "the user's 'own language first' rule (own-language declarations beat cross-language matches, outranking import order) is stated but not specified — settle the exact rule before anyone implements it"
---

# Specify "own language first" before implementing it

- **Type:** decision — **Track U**
- **Opened:** 2026-08-10, filed from
  [[bug-c-pascal-math-names-hijack-libc-through-pxxcio]] as a note, not as work.
  The user's instruction on that ticket was explicit: *out of scope unless it
  falls out for free — note it, don't build it.* This ticket is the note.

## The rule as stated (user, 2026-08-10)

> **Own language first:** a declaration from the caller's own language beats a
> cross-language match, and that outranks import order.

## Why it is not yet implementable

The principle is clear and the boundary is not. Every question below changes
what the compiler does, and none is answerable from the code:

1. **What is "the caller's own language"** — the frontend that parsed the call
   site, or the unit the call site is in? A C source `#include`d into a Pascal
   unit's compilation is not obviously either.
2. **Is a `lib/crtl` header a C declaration for this purpose even when the body
   is Pascal?** The `__pxx_*` PAL entry points are declared in C headers and
   defined in Pascal; the rule must not break them.
3. **Does it apply to the Pascal side symmetrically** — does a Pascal `uses`
   clause now lose to a C declaration the program never mentioned?
4. **Does it change resolution, or only tie-breaking?** "Beats a cross-language
   match" reads as a hard precedence; "outranks import order" reads as a ranking
   term. Those are different implementations and the second is much cheaper.
5. **Is case-sensitivity part of it?** The collisions this rule exists to kill
   are all case-INSENSITIVE matches (`Pow` vs `pow`). A narrower rule — a
   cross-language match must be exact-case — might close the class without
   touching precedence at all, and is a much smaller change.

## What is already true, so the fix is not urgent

The one prelude that made every C program a victim is gone: `pxxcio` no longer
does `uses math`, so the Pascal RTL is not in scope for C name resolution by
default. What remains is a user program that itself imports a Pascal unit next
to C code, plus the `__crtl_`-prefixed workarounds in `lib/crtl/src/math.c`
(`exp`, `log2`, `log10`, `sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`, `hypot`)
that exist only because of this. Settling the rule is what lets those names go
back to being spelled normally.

## Recommendation

Take **question 5 first as a measurement, not a decision**: count how many of
the known collisions (b377 `exp`, `Pow`/`Log`/`CopySign`, `NaN`, `Log2`/`Log10`,
`Floor`/`Ceil`) survive a rule of *"a cross-language name match must agree on
case"*. If that is all of them, it is the whole fix, and questions 1-4 never
need answering. If it is not, the answer to 4 ("precedence, or tie-break?") is
the next thing to decide and the rest follow from it.

## MEASUREMENT 2026-08-10 — question 5 comes back "all of them"

The recommendation above was to measure question 5 before deciding anything.
Done, at `243c8c8f5`. Every Pascal-side declaration in the known collision set
is CAPITALISED and every C-side name is lowercase:

| C name | Pascal decl (lib/rtl) | collides if a cross-language match must agree on case? |
| --- | --- | --- |
| `exp` | `Exp` | no |
| `nan` | `NaN` | no |
| `log2` / `log10` | `Log2` / `Log10` | no |
| `floor` / `ceil` | `Floor` / `Ceil` | no |
| `pow` / `log` | `Power` / `LogN` | different NAMES — never collided |
| `copysign` | none | no Pascal declaration at all |

So the narrow rule — **a cross-language name match must agree on case** — closes
the entire known class, and questions 1-4 (what counts as "the caller's
language", the C-header/Pascal-body PAL entries, symmetry on the Pascal side,
precedence-vs-tie-break) never have to be answered to fix it.

Caveat, stated plainly: that is the KNOWN collision set, the one this ticket
lists. It is not proof that no case-agreeing cross-language collision exists —
only that none has been observed. The rule degrades safely if one appears (a
real collision then still resolves by the existing order, i.e. today's
behaviour), so it is not a trap.

## Two questions were tangled here

The user's rule as stated — *"in Pascal `import math` prefers math.pas, in C we
prefer math.c, in NilPy we prefer tkhtmlview.py over tkhtmlview.pas"* — is about
**module resolution**: which FILE an import name resolves to. That is already
how it works: the Pascal `uses` path (parser.inc:29827+) builds `<name>.pas`
candidates only, and each frontend searches its own extension. No cross-language
file search happens.

This ticket is about **symbol resolution**: which declaration of `Log2` wins once
a Pascal unit and a C header are both in ONE symbol table. Same slogan, different
machinery — and it is the symbol half that carries the awkward cases (the
`__pxx_*` PAL entry points are declared in C headers and DEFINED in Pascal, so a
naive "own language first" must not break them).

Worth keeping the two apart in whatever lands: the module half is settled and
mostly built; the symbol half is what needed a rule, and the measurement above
says a narrow case rule suffices.

## SUPERSEDED 2026-08-10

The user settled the rule: **if a symbol is defined in more than one language,
the native language wins** — a hard precedence, outranking import order. And the
reframing that matters: C reaching into Pascal's math was the design error, not
the naming. Duplicate per-language implementations are the intended outcome.

Re-filed as work: **[[feature-a-own-language-first-symbol-resolution]]**.
Kept as the record of the measurement (case-agreement closes the known class)
and of the module-vs-symbol distinction. Prio dropped to 5.
