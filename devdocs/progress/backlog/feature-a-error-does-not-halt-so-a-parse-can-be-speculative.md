---
track: A
prio: 45
type: feature
summary: "`Error()` calls `Halt` directly, so nothing in the compiler can trial-parse and back out. That blocks NilPy's type inference (which needs to read an as-yet-unseen name speculatively), and it is also why the compiler stops at the FIRST error. Make the error path recoverable; several unrelated wants fall out of the same change."
---

# `Error()` halts, so no parse can be speculative

- **Type:** feature (compiler core) — **Track A**.
  Split out 2026-08-14 by the user while re-pricing
  [[decide-reprice-nilpy-ast-typing-module-scope]]:

> *"It makes no sense to optimize a halt()."*

## The problem in one line

`Error()` calls `Halt` directly. So there is no way to attempt a parse, discover
it does not work, and carry on — the attempt kills the process.

## What that blocks, that we already know about

1. **NilPy module-scope type inference.**
   [[feature-n-nilpy-ast-typing-module-scope]] wants a pre-pass that trial-parses
   the RHS of a binding whose name has not been seen yet. It cannot, so it
   carries a hand-maintained "safe shape" list instead, and anything not on the
   list widens to `tyVariant`. Its own note calls the recoverable pre-pass *"the
   real close"*, after which the safe-shape list **disappears** rather than
   being extended. That ticket is now prio 8 because it cannot be worked until
   this lands.
2. **Multiple errors per compile.** Halting at the first one is the same
   constraint wearing a different hat: a user fixing ten mistakes gets ten
   compile cycles.
3. **Any future speculative parse** — overload resolution that wants to try a
   shape, a frontend probing whether a construct is legal before committing.

The pattern to notice: three unrelated wants, one plumbing cause. That is
usually the sign the plumbing is the real ticket
(`devdocs/dev/root-cause-over-microfix.md`).

## Shape, not a prescription

The obvious approach is an error *sink* — collect rather than halt, with an
explicit "abort now" for the cases that genuinely cannot continue (a corrupt
read, an internal invariant). Two things to work out rather than assume:

- **What state must be unwound** when a speculative parse fails. A trial parse
  that has already registered symbols, allocated types or emitted IR has to be
  rolled back or scoped, and that is the real work here — not the error call
  itself.
- **Which errors are genuinely fatal.** Turning everything recoverable risks a
  compiler that limps on producing cascading nonsense, which is worse than
  stopping. FPC's own behaviour is a reasonable reference point.

## Not urgent, but it unblocks more than it looks

Nothing is broken today. Filed at 45 because it is the shared cause behind at
least three separate wants, and because one of those (NilPy inference) is
otherwise permanently parked.

## Gate

A parse that fails inside a speculative attempt leaves the compiler able to
continue and produce a correct result for the non-speculative path; `make
compiler/pascal26` fixedpoint byte-identical; `tools/gate.sh quick` GREEN.
Plus the property that makes it worth doing: a file with two independent syntax
errors reports both.
