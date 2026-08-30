---
slug: feature-extended-type-support
track: A+F
prio: 25
type: feature
blocked-by: []
superseded-by: feature-a-extended-is-an-alias-for-double
summary: "SUPERSEDED 2026-08-30 by [[feature-a-extended-is-an-alias-for-double]], which is the designated umbrella for the Extended cluster. Kept as a gravestone because it is cited from three places; its one unique constraint (the RTL ships Single + Double overloads only, on purpose) has been folded into the umbrella."
---

# Proper `Extended` type support (currently aliased to Double)

> **SUPERSEDED 2026-08-30 → [[feature-a-extended-is-an-alias-for-double]].**
> Do not work this ticket. Three overlapping umbrellas existed in three folders
> (`rainy-day/`, `float/`, plus the Track U decide in `backlog/`); the `float/`
> one carried the only real scope analysis, so it became the umbrella and this
> file is kept only so the inbound citations below still resolve.

- **Type:** feature (compiler) — **Track A**
- **Status:** superseded (was: rainy-day)
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")

## Why this file still exists

It is cited from three places that would otherwise dangle:

- `float/bug-b-rounding-api-gaps-setroundmode-roundto-lround.md:113` — "targets
  Single + Double only ([[feature-extended-type-support]])"
- `rainy-day/goal-compile-fpc-compiler.md:151`
- `done/feature-float-math-and-demo.md:13`

Renaming or deleting would break those links for a grouping the umbrella already
provides, which is the same reasoning `meta-float-accuracy-policy` gives for not
re-slugging the float cluster.

## Original goal (kept verbatim)

Real `Extended` support. Right now `Extended` is **cheated as `Double`**
(see feature-extended-alias-or-reject, done). The user does not want to invest in
true 80-bit Extended yet; libraries must keep working under the alias.

## Constraints / notes (kept verbatim)

- Until this lands, **RTL libraries target Single + Double only** and assume
  `Extended = Double`. `lib/rtl/math.pas` intentionally provides only Single +
  Double overloads (no Extended).
- True Extended means an 80-bit x87 path on i386/x86-64 (and a decision for
  targets without 80-bit hardware — soft-float or reject). Interacts with
  feature-real-cross-target-consistency.

## Log
- 2026-06-22 — Filed by Track B while building the math library; deferred per user
  (Extended not a priority until properly supported).
- 2026-08-30 — **Superseded.** Owner ruled Extended will be implemented properly
  eventually, and asked for the whole cluster to be consolidated in `float/` so
  it can be worked in one session. This ticket's only content the umbrella did
  not already have — the deliberate Single+Double-only RTL surface — is now
  workstream 4 there. Moved `rainy-day/` → `float/` in the same pass.
