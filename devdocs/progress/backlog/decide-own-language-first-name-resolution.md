---
track: U
prio: 60
type: decision
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
