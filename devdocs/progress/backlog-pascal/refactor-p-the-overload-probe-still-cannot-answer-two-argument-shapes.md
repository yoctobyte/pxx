---
slug: refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes
title: "Two argument shapes no side channel answers, so the method gate still abstains where the free path decides"
track: P
prio: 30
type: refactor
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "The overload probe now fills the five argument-match channels and refuses on MatchArgRecMismatch, but it still cannot run the full TypesCompatible check, because two argument shapes have no channel that answers them: a generic type parameter is tyUnknown at the declaration, and a bare routine name used as a procedural value types as neither. Both were MEASURED refusing legal code. Until each has an answer the single-candidate gate keeps its narrow allowlist, so a wrong argument to a single-candidate method is still accepted whenever neither the channels nor the allowlist can speak."
---

# The residual from the channel refactor

[[refactor-p-the-overload-probe-cannot-see-the-argument-match-channels]] is done:
`FillMatchArgChannelsAt` is shared, the probe fills it at the parameter slot, and
the `nCand = 1` gate calls `MatchArgRecMismatch` -- the free path's own refusal
predicate. That closed a silent wrong value (an array argument binding a scalar
parameter through a method call, printing the array's address).

Its body then says the allowlist *"can widen to the full check and delete its own
comparison."* **It cannot, and the reason is not the channels.** Two of the four
rows in that ticket's measurement table have a dash in the "channel that knows"
column, and filling all five answers neither:

| shape | why kinds are wrong | what would answer it |
| --- | --- | --- |
| `slist.Add('test', l)` | a generic type parameter is `tyUnknown` at the declaration, so every argument looks incompatible with it | a "this parameter is an unbound generic" bit, or resolving the instantiation before the gate runs |
| `inherited Sort(ItemPtrCompare)` | a bare routine name as a procedural value types as neither a pointer nor the signature | a channel saying "argument j is a routine reference", which the free path gets from its AN_PROCADDR retry rather than from a channel |

Measured when a naive `TypesCompatible` gate was tried: conformance went
346 -> 338/8 and the fgl rung 7/7 -> 0/7. Those numbers are from the parent
ticket's original measurement and predate the channels; **they are the reason to
re-measure rather than a current baseline** (today's baselines are 347/2 and
7/7).

## Why this is worth doing rather than leaving

The gate is SOUND but not COMPLETE: it refuses only what it can prove wrong. So a
wrong argument to a single-candidate method is still accepted whenever neither
the channels nor the narrow allowlist can speak -- the same class of silent wrong
value the parent ticket closed one instance of, minus the instances the channels
happen to cover. The parent's own history is the argument: every one of the five
channels exists because somebody hit a wrong answer first.

## The trap, restated because it caught the parent twice

**Calling the shared predicate is not the same as reaching the shared answer.**
`MatchArgNilOk` exists and gates on `MatchArgNil[]`; calling it from a path that
does not fill the channel answers False for every nil. Whatever is built for the
two rows above has to supply the FACT, not just call the function that reads it.

And the channels are globals with no per-call lifetime -- the four `*Valid` flags
are set True in one place and False only where a reader explicitly declares them
invalid (`bc2fe10f1`, `5dbd56a3c`). Any new filler must fill in a window that
contains no parsing, or a nested probe will clobber it; both existing fillers do,
and both say so.

## Gate

The parent's, unchanged and re-measured rather than quoted: the four rows in its
table compiling clean, conformance at its TRUE baseline (347/2, and assert the
suite is present -- absent, the harness prints SKIP and exits 0), fgl 7/7,
`test_method_arg_typecheck_{ok,fails}.pas` and
`test_method_array_arg_{ok,scalar_param_fails}.pas` unchanged, plus a
before/after compile diff over the whole Pascal test corpus with a
discrimination control -- a no-change sweep cannot tell "safe" from "the corpus
never reaches the arm".
