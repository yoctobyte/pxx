---
track: T
prio: 50
type: feature
owner: unassigned
blocked-by: []
summary: "DECIDED 2026-08-19: a Track T tier job that compiles compiler.pas at every -O level and DIFFS the results across levels. Not in the per-fix loop — quick-gating must not slow down. The point is optimizer differential coverage as Track O ramps up, NOT the code-size issue that surfaced it; compiler.pas is the largest, densest program we can run the optimizer over."
---

# Tier job: self-compile differential across `-O` levels

**Implements [[decide-should-the-gate-prove-self-compile-at-more-than-one-o-level]]**
(user, 2026-08-19). Filed as work because a decided ticket that is never re-filed is
invisible to `ready`/`next`.

## What to build

A Track T tier job that compiles `compiler/compiler.pas` at **every** `-O` level and
**compares the results across levels**.

**Not in the per-fix loop.** The user was explicit that this must not hinder quick-gating.
The dev loop stays `make compiler/pascal26` + repro + `tools/gate.sh quick`.

## Build it as a DIFFERENTIAL, not as a smoke test

The framing matters more than the mechanism. "Does `-O0` still compile" is the weak
version, and its motivation is already spent: the failure that prompted this was
`MAX_CODE`, a **runaway guard** rather than a real constraint, now 8 MB to 16 MB with the
default build at 44%. Size will not catch anything again soon.

**The lasting value is optimizer coverage.** If the compiler built at `-O0` and at `-O3`
disagree about *anything*, that is an optimizer bug — and `compiler.pas` is the largest,
most edge-case-dense program available to run the optimizer over. **This grows in value as
Track O ramps up** (new `-O3` passes, per-pass promotion to `-O2`); it is the cheapest
optimizer-differential the project owns.

## Most of it exists already

The bench harness already emits `CANARY-DIFF vs -O0` for the `-O2` and `-O3`
`selfcompile` rows — a cross-level comparison, and the thing that surfaced the original
failure. **Formalise and extend that into a tier job rather than building a second
mechanism.** T owns tier composition and should size it.

One behaviour to preserve from that incident: when the `-O0` build failed, `-O2` and `-O3`
reported `CANARY-DIFF vs -O0` purely because the baseline did not exist — **three red rows,
one defect.** The job should distinguish "baseline missing" from "levels genuinely
disagree", or every future failure reads as three.

## Known and counter-intuitive

**Lower `-O` levels emit MORE code**, so a build that fits at `-O2` can overflow at `-O0`.
The error text names this now; the job's reporting should not assume the opposite.

## Gate

Track T's own tooling gate, and test the tooling with QUICK tiers plus a scratch bare repo
rather than long runs.
