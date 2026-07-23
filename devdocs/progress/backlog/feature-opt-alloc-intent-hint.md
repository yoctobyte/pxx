---
track: A
prio: 25
type: feature
---

# Allocation-intent hint: tell the RTL growth policy how a buffer will be used

Track O (optimization; heap allocator + a thin frontend flag) — lands under A's
gate (self-host byte-identical). Deferred / earn-it-first: no live profile is
pulling this. Filed so the design is on record, not to schedule it.

## Problem
The allocator cannot see intent. A one-shot `s := s + c` (a directory path, a
known-length transform) and an unknown-length accumulation in a loop hit the
SAME growth path, so a single global growth policy is wrong for both. The intent
is legible at the CALL SITE / in the AST, not at runtime.

## Shape (small — two flags, not a predictive model)
Thread a tiny intent enum from the frontend through the managed-string / dynarray
alloc lowering into the RTL growth decision:

- `exact` / `compact` — final size is known or the value is done being built →
  allocate exact, no slack, trim on finalize. (Most `s + c` one-shots, `upper`/
  `lower`, path building.)
- `growing` — accumulation whose length is unknown up front → amortised growth
  (1.5x = `n + n>>1`, sub-golden so freed blocks stay reusable; see the
  reuse note in [[idea-adaptive-heap-growth]]), page/size-class-rounded, ratio
  capped by a per-target slab so 1 GB + 1 B never doubles to 2 GB.

## The free 80% (do this part first if anything)
A function's Result string being built is ALREADY special (the return / NRVO
path), so the RTL can auto-apply `growing` slack + trim-at-return to any
Result-typed managed string with ZERO frontend work. That captures the common
"build a string and return it" case. The explicit `growing`/`exact` flag is only
needed for non-Result locals accumulated in a loop.

## Relationship
This is the middle slice between the concrete
[[perf-nilpy-remaining-perbyte-string-builders]] (fix known sites by hand, do
now) and the research [[idea-adaptive-heap-growth]] (which supersedes this). Do
the smallest slice a profile actually demands; never top-down.

## Gate
`make test` + self-host byte-identical (touches shared RTL / alloc lowering) +
cross where a target's growth policy differs (ESP wants a smaller cap). Land the
Result-auto-slack part alone first; the explicit flag is a follow-on.
