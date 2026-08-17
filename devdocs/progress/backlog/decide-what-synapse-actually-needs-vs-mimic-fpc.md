---
slug: decide-what-synapse-actually-needs-vs-mimic-fpc
track: U
prio: 20
status: backlog
---

# Synapse builds under `--mimic-fpc`. What does it actually NEED?

> **DEPRIORITISED 45 -> 20 (owner, 2026-08-17): we are chasing the wrong fox.**
> *"We already implemented our own TCP stack, including SSL. Synapse is a TEST
> library, not something we will build on in practice."*
>
> That removes the load-bearing justification this ticket was written on. It
> argued that `--mimic-fpc` weakens the claim we could make to Synapse's author,
> and that five more smokes would cement the invocation — both true, and both
> worth little once Synapse is a **corpus** rather than a **dependency**. A test
> surface has to be honest about what it measures; it does not have to be
> beautiful to integrate against, because nothing integrates against it.
>
> **The lesson for whoever reads this next**, and it is the reason the ticket is
> kept rather than deleted: the coordinator built a case for *compiler* work
> (directory-scoped define manifests, Track A) whose entire motivation was a
> library we will never depend on. Every individual observation in it was correct.
> The measurement was fine. It was pointed at the wrong subject — the same failure
> this repo keeps recording, arriving this time as **misplaced priority** rather
> than a wrong conclusion. Before proposing core work, ask what depends on the
> thing that motivated it.
>
> **What survives:** Synapse stays a valuable corpus (real third-party Pascal,
> compiles as-is, byte-exact codec vectors against FPC), so `--mimic-fpc` remains
> the supported way to build it and nobody should hand-narrow it. Scoped
> `pxxlib.cfg` manifests may still be worth building — but they must be justified
> by a library we DO build on, or by the self-build safety argument, never by this
> one.

> **Scope (owner, 2026-08-17): this is about PASCAL programs importing Synapse.**
> NilPy importing Synapse is the wrong measurement and is not a goal — Python has
> its own TCP stack, so a `.npy` reaching for `blcksock` would be solving a
> problem the language already solved. Verified clean at filing: no `.npy` in the
> tree imports `synapse` / `blcksock` / `synautil`.
>
> The distinction matters because the two compatibility mechanisms are separate
> and it would be easy to merge them by accident: **Pascal** libraries are
> configured by the curated define set (`PasApplyMimicDefines`, and eventually the
> scoped `pxxlib.cfg` manifest), while **NilPy** compatibility goes through the
> `mimic_<name>` shim slot. A per-library manifest is a Pascal-corpus concept.

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

## CORRECTION — the per-library config EXISTS. Twice-wrong reasoning below.

The owner said flatly: *"we DID craft a config per imported library, long ago."*
Correct. Two wrong conclusions were filed here before that landed, both from
searching for the wrong artefact:

1. First: "no `.cfg` files, so it was never built" — a filename guess.
2. Then: "designed in `ad9811a63`, ticket closed early, only the fallback
   shipped" — closer, still wrong about what shipped.

**What actually exists:** `compiler/lexer.inc:876`, `PasApplyMimicDefines`, whose
own comment calls it *"the **curated** FPC 3.2.2 x86-64-Linux define set so
identity-probing library headers (**jedi.inc / Synapse**) select their FPC path
instead of Kylix/Delphi."* It sets `FPC`, `UNIX`, `ENDIAN_LITTLE`, `VER3`,
`VER3_2`, `VER3_2_2` and the `FPC_VERSION`/`RELEASE`/`PATCH`/`FULLVERSION`
values. That curation IS the per-library config — it was crafted around Synapse's
identity probes, which is why Synapse compiles as-is.

It also already has **two** delivery paths, not one: the `--mimic-fpc` CLI flag
and a `{$MIMIC FPC}` source directive, the latter giving per-source-file
granularity today.

**So the lesson is the recurring one, in the coordinator's own reasoning this
time:** searching for `*.cfg` returned nothing, which was a TRUE fact about the
WRONG subject — "is there a file named like a config" is not "does the
configuration exist". Two successive conclusions were built on it, each more
confident and more specific than the last, and the second one cited real commit
history, which made it more persuasive rather than more correct.

## What is ACTUALLY missing: scoping, not configuration

The curated set applies **globally** (flag) or **per source file** (directive).
What `ad9811a63` designed and `feature-dynamic-include-paths-config` (still
`backlog/`) holds is the missing third thing: applying it automatically to a
library's DIRECTORY TREE, via `lib/synapse/pxxlib.cfg` and a per-unit define-scope
push/pop keyed to the unit's source directory, nearest-ancestor manifest wins,
scope following the unit being COMPILED rather than the caller.

Why that matters beyond tidiness — a hazard is recorded in the same comment:

> *"NEVER call during a self-build — the compiler's own `{$ifdef FPC}` means
> 'real FPC, not PXX'."*

That is a rule enforced by remembering. Directory scoping would make it
structural: the manifest applies to `external/synapse/**` and cannot reach
`compiler/**`, so the landmine stops being reachable rather than stopping being
stepped on. Same shape as the uses-never-leaks principle.

## Recommendation

**Do not narrow the flag by hand.** The define set is curated, deliberate, and
already correct — narrowing it by experiment would be re-deriving work the owner
did months ago. The open item is scoping it: finish
`feature-dynamic-include-paths-config`, ship `lib/synapse/pxxlib.cfg`, and the
global flag becomes the fallback it was designed to be.

Wiring the five extra synapse smokes under `--mimic-fpc` is then fine in the
interim — it is the supported path today, not a shortcut. Revisit when scoping
lands.

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
