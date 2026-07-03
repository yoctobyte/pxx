# Rust frontend — generics with trait bounds

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 3/12. Depends on
  [[feature-rust-frontend-skeleton]].

## What it does

Extend the existing monomorphization engine (`GenericFuncs`/`GenericMethods`,
defs.inc ~679-789 — already does Pascal-generic specialization) to accept
`where`-clause / inline trait bounds (`fn f<T: Display>(x: T)`) and check
that the bound is satisfied at specialization time (the concrete `T` must
have an `impl` of the required trait reachable).

Not new conceptually — same specialize-per-call-site machinery already
proven for Pascal generics — but real engineering volume: real-world dep
code (`shakmaty` alone: 123 generic functions, 63 `impl<T>` blocks, 57
`where` clauses) leans on this heavily, more than the app code itself does.

## Scope

- Bound satisfaction check at specialization, not a general trait-coherence
  solver — reject with a clear error if unsatisfied, don't try to be clever.
- No specialization/overlapping-impl resolution beyond what's needed for a
  single unambiguous match (Rust forbids overlapping impls anyway).
- Multiple bounds (`T: Display + Clone`) — AND of individual checks.

## Acceptance

- Generic function/struct with a single trait bound specializes correctly
  per call site, rejects a concrete type missing the trait with a clear
  compile error (not a silent miscompile or generic IR crash).
- Multi-bound case works.
- Existing Pascal-generic tests unaffected (this extends, doesn't replace,
  the existing specialization path).

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
