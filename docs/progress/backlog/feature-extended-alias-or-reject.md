# Extended: formalize as Double alias (or reject)

- **Type:** chore (type system honesty)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Priority:** low

## Problem

`Extended` is half-real. `tyExtended` exists (defs.inc:453, size 10, x87
load/store on x86-64) but **all arithmetic runs in SSE2 double** — there is no
true 80-bit math. On cross targets it's treated as double. So `Extended` today is
effectively a Double that occasionally costs 10 bytes of storage and an x87 round
trip, with no extra precision.

## Decision needed

Pick one:
- **(a) Alias to Double everywhere** (drop the 10-byte x87 storage; `Extended =
  Double`). Honest, simplest, matches what the arithmetic already does. Cost: a
  hair of FPC source-compat where code declares `Extended` expecting 80-bit (we
  don't target that precision anyway).
- **(b) Reject `Extended`** on cross targets (and document x86-64 as
  double-precision-despite-the-name).
- **(c) Real 80-bit** — explicitly NOT wanted (no demand, big x87/soft cost).

Recommendation: (a). Low priority; no user demand. Filed so the half-state is
tracked, not silently shipped.

## Notes

- Related: [[feature-single-first-class]] (the *other* end of the float-width
  spectrum — that one we DO want first-class).
