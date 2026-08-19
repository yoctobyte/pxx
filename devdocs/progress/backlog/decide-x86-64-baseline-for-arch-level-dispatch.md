---
track: U
prio: 40
type: decide
blocked-by: []
summary: "What x86-64 baseline does pxx target? The ticket says outright that the baseline row is the user's call, not an engineering one — and the gate box constrains it hard: plexus is Ivy Bridge (AVX, no FMA) = x86-64-v2, so a v3 baseline would SIGILL on the machine that gates every push. Whoever claims the feature otherwise has to guess something the project cannot un-choose."
---

# What x86-64 baseline does pxx target?

**Split out of [[feature-opt-arch-level-and-dispatch]] 2026-08-19**, second use of the
"blocked on judgement, not on engineering" outcome from the A/P/C feature triage. The feature
ticket says it in its own words: *"The baseline row is the user's call, not an engineering
one."* Left typed as a feature it reads as buildable, and whoever claims it has to guess a
baseline **the project cannot un-choose** — raising a baseline later breaks every user on
older hardware, so this is a one-way door.

## The constraint that shapes the answer, measured

**plexus — the box that gates every push — is Ivy Bridge: AVX, but no FMA. That is
x86-64-v2.** So a **v3 baseline would SIGILL on the gate itself**, not merely on some
hypothetical user's machine. Any answer above v2 has to come with a plan for the gate box
before it can mean anything.

This is the kind of fact that is cheap to establish and expensive to discover late, so it is
recorded here rather than left in the feature ticket's body.

## The fork

Roughly, the choices are:

- **v1 (baseline x86-64, SSE2)** — runs everywhere, leaves performance on the table.
- **v2 (SSE4.2, popcnt)** — what the gate box supports; the conservative modern floor.
- **v3 (AVX2, FMA, BMI)** — the usual "modern desktop" line, and **currently unrunnable on
  our own gate**.
- **Runtime dispatch** — build multiple paths, select on CPUID. No baseline decision needed
  for correctness, but it costs code size and complexity, and it interacts with
  [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]], whose whole point
  is *smaller*.

## Why it cannot be settled by an engineer

The trade is about **who we are willing to stop supporting**, which is a product question. A
worker can measure the speedup of each level and cannot decide whether it is worth excluding
older hardware — and the answer is not recoverable once shipped and depended upon.

## Recommendation

**v2 as the compiled baseline**, because it is the highest level our own gate can execute, so
it cannot silently break the thing that verifies every commit. Treat anything above it as
**runtime dispatch** if it is wanted at all — which keeps the one-way door shut and defers the
cost to the sites that actually benefit.

## What happens after

Once decided, **re-file the work into Track A (the O lane)** and move this to `decided/`.
`ready`/`next` do not read decisions, so a decision that is never re-filed is invisible and
gets rediscovered.

## Log
- 2026-08-19 — split from the feature ticket during the A/P/C feature triage.
