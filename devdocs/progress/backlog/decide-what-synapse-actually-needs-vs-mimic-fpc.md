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

## The question — CORRECTED, this is not an open design question

The coordinator first wrote that the per-library config mechanism "was designed
and not built", inferred from finding no `.cfg` files. That was a filename guess
answering the wrong question. What the history actually shows (`ad9811a63`,
2026-06-19, "docs(config): per-library scoped define manifests"):

The design exists and is specific. Manifest = `lib/synapse/pxxlib.cfg`, a small
per-library build profile carrying defines/undefs/dialect mode/include paths.
Load-bearing primitive = **per-unit define-scope push/pop keyed to the unit's
source directory**, nearest-ancestor manifest wins. Scope follows the unit being
COMPILED, not the caller — so cross-`uses` stays clean, siblings are isolated, and
the user program is untouched. That non-virality is the whole point, and it is the
same principle as the uses-never-leaks rule.

**The state is the finding:**

| ticket | what it holds | where it is |
| --- | --- | --- |
| `feature-mimic-fpc` | reframed as a scoped manifest, *"global `--mimic` becomes a fallback"* | **`done/`** |
| `feature-dynamic-include-paths-config` | the define-scope primitive the manifest needs | **`backlog/`** |

No `pxxlib.cfg` exists; no manifest loader is in `compiler/`. So **the fallback
shipped and was marked done, while the mechanism it was a fallback FOR was left in
the backlog.** `--mimic-fpc` is not a shortcut someone chose today — it is the
only path that exists, because the ticket describing it as temporary was closed
once the temporary part worked.

This is the repo's own recorded landmine: *check the design was built before
reasoning about it* — one numbered work item undone leaves a design that reads as
finished. Five sessions were lost to that shape once already.

Note the design also answers a question the owner raised separately: it selects
Synapse's branch by scoping `undef FPC` to the library tree, which *"dodges the
`{$ifdef FPC}`=real-FPC landmine AND cannot leak"*. The umbrella flag achieves the
branch selection with neither property.

## Recommendation

**Do not narrow the flag by hand, and do not wire the five extra synapse smokes
under `--mimic-fpc`.** The right answer is already designed: finish
`feature-dynamic-include-paths-config`, ship `lib/synapse/pxxlib.cfg`, and let the
umbrella become the fallback it was always meant to be.

The decision for the owner is therefore **priority, not direction** — this is
Track A work (define scoping is compiler internals), it is currently at backlog
priority, and it blocks: the honest synapse claim, the five unwired smokes, and
every future library that needs its own defines (IDF, gtk, usr-include were all
named in the original design as manifest consumers).

Secondary, and worth an explicit answer: **should a closed ticket be reopened when
the follow-up it depended on stayed in the backlog?** `feature-mimic-fpc` is in
`done/` describing a state that is not true — its own text says the global flag is
a fallback. Whatever the answer, that ticket's text should not keep asserting a
design that was never completed.
