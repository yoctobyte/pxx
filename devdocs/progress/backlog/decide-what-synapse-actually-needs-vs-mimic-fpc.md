---
slug: decide-what-synapse-actually-needs-vs-mimic-fpc
track: U
prio: 45
status: backlog
---

# Synapse builds under `--mimic-fpc`. What does it actually NEED?

**Read time: 2 minutes.** Owner already stated the answer; this records it and
asks how far to take it.

## What we do today

`Makefile:9815` builds the synapse corpus with the umbrella dialect switch:

    $(PXX_STABLE) --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix

It works because of `lexer.inc:880`: under that mode the `FPC` symbol is set, so
identity-probing library headers (jedi.inc, Synapse's own) select their **FPC**
branch rather than the **Kylix/Delphi** one.

## Why that is the wrong shape (owner, 2026-08-17)

> *"Synapse likes if we define FPC. It doesn't need the full mimic-FPC. And even
> worse, we took the path that defines Kylix/POSIX. So it has a bunch of custom
> directives to make it work."*

So the branch selection we want is a **side effect** of a much broader dialect
switch. Three costs:

1. **It hides what is actually required.** Nobody can say which parts of
   `--mimic-fpc` synapse depends on, because the umbrella supplies all of them.
2. **It weakens the claim.** "Synapse compiles with `FPC` defined" is a far
   stronger statement than "compiles under our FPC-mimicry mode" — the first says
   we are a Pascal compiler the library recognises, the second says we emulate a
   specific one. The owner intends to approach the synapse author (Lucas) once
   the compiler is stable, and that first impression is spent once.
3. **It is about to be replicated.** Track T's triage found five more synapse
   smoke tests that build once `--mimic-fpc -Fuexternal/synapse` is supplied.
   Wiring them that way cements the invocation five more times, and a thing that
   works is a thing nobody revisits — the same failure as recording our own output
   as an expectation (`decide-what-an-unwired-test-may-assert`).

## The question

Narrow the invocation to what synapse genuinely needs — plausibly `{$DEFINE FPC}`
plus a named set of directives — and if so, is that a **per-library config file**?
The owner referred to per-library configuration as designed; the only `.cfg` in
the tree is `test/incdir_fi/tinc_fi.cfg`, a test fixture, so either the mechanism
is spelled differently or it was designed and not built. **Establish which before
building anything** — the repo's own rule after five sessions were lost debugging
a design that had not been built.

## Recommendation

Do NOT wire the five additional synapse smokes under `--mimic-fpc`. Determine the
minimal flag set first — the experiment is small (drop the umbrella, add `FPC`,
see what breaks) and it answers the question by measurement instead of argument.
Then wire all seven the honest way at once.

Not urgent. It blocks nothing; it only stops us multiplying a shortcut.
