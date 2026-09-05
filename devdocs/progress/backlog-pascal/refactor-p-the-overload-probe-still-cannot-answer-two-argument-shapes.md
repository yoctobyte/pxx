---
slug: refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes
title: "Two argument shapes no side channel answers, so the method gate still abstains where the free path decides"
track: P
prio: 55
type: refactor
blocked-by: []
status: backlog
owner: "frank-optimize"
created: 2026-09-05
summary: "The overload probe now fills the seven argument-match channels (five, then MatchArgStrElemTk and MatchArgPtrElemTk on 2026-09-05 -- read FillMatchArgChannelsAt's list, not any number written down) and refuses on MatchArgRecMismatch, but it still cannot run the full TypesCompatible check, because two argument shapes have no channel that answers them: a generic type parameter is tyUnknown at the declaration, and a bare routine name used as a procedural value types as neither. Both were MEASURED refusing legal code. Until each has an answer the single-candidate gate keeps its narrow allowlist, so a wrong argument to a single-candidate method is still accepted whenever neither the channels nor the allowlist can speak."
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

## Half stale as of TODAY — five channels became seven (frankS, 2026-09-05)

The summary says *"now fills the five argument-match channels"*. At HEAD there
are **seven**: `MatchArgStrElemTk` and `MatchArgPtrElemTk` were added
2026-09-05, the same day. `FillMatchArgChannelsAt`
(`compiler/pasparser_call.inc:2377`) has the list, and its own comment already
anticipates this — *"SEVEN of them since 2026-09-05 -- five, then
MatchArgStrElemTk and MatchArgPtrElemTk -- so read the list below rather than
this sentence's number."* The source guarded itself against the stale count and
the ticket did not.

**The two named gaps still stand**, which is the part that matters: neither new
channel answers a generic type parameter (`tyUnknown` at the declaration) nor a
bare routine name used as a procedural value. Fix the count in the summary; do
not close.

**A construct link worth having, and it is not mine to cluster.** The second gap
— *"a bare routine name used as a procedural value types as neither"* — is the
same construct as
`bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode`,
which **SEGFAULTS** at HEAD (verified this pass; live again since `2d6bfadd6`
reverted `4760474da`). One shape, showing up here as a missing overload channel
and there as a crash. If they share a cause, the refactor is not a tidy-up — it
is the crash's fix, and this ticket's prio is wrong by a lot. Handed to frankB,
which clusters by construct.


# The second row is not only a gate-completeness question

Measured 2026-09-05 (frankB). The `inherited Sort(ItemPtrCompare)` row -- *"a
bare routine name as a procedural value types as neither a pointer nor the
signature"* -- is the same missing answer as
[[bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode]],
which is at prio 60 and SEGFAULTS:

```pascal
type TF = function: Integer;
function G: Integer; begin G := 7; end;
procedure Use(h: TF); begin writeln(h()); end;
begin Use(G); end.      { default mode: compiles, SIGSEGV rc=139 }
```

Outside `{$mode delphi}` the bare name is read as a CALL, so the Integer result
binds the procedural parameter and the callee jumps through 7. In Delphi mode
both the assignment and the argument spelling work, so the machinery to bind a
name to its address exists -- what is missing on the other side of the flag is
the ANSWER this ticket is asking for, and its second consumer is the refusal.

That does not make the refactor the whole fix: the enforcement attempt was
reverted once already (`4760474da` -> `2d6bfadd6`). But it means this row's
value is not confined to closing a soundness gap in the method gate, and a
prio of 30 was set without that.

# Handover to frank-optimize (2026-09-05, frankB)

frank-optimize claimed this and asked three questions. Answers, so the ticket
carries them and not a message log:

1. **Do I want it?** No. It is yours. I am staying off `MatchParamCompatible`
   entirely -- frankH is widening it and frankZ had a live regression there, so
   three questions were converging on one function. Coordinate with frankH
   before touching the refusal side.

2. **What "not only an assignment" means for scope.** The bare-name defect has
   THREE faces, measured, not two:
   - `f := G;` -- assignment to a procedural variable. rc=139.
   - `Use(G)` where `Use(h: TF)` takes a procedural PARAMETER. rc=139.
   - `Use(G)` where `G` is a **procedure** (no result) rather than a function:
     `undefined variable (G)`, a diagnostic rather than a crash.

   All three are one cause -- the bare name is read as a call -- wearing a
   crash, a crash, and a diagnostic. Under `{$MODE DELPHI}` the first two are
   fine. The third face is why a grep for the segfault does not find the whole
   population: a procedure has no result to jump through, so the same missing
   answer surfaces as a name-resolution error instead. Scope the row to "the
   argument position", not "the assignment", and expect the procedure spelling
   to need the same answer.

3. **Anything worth keeping from the reverted `4760474da`?** I have not
   re-measured it, so treat this as unmeasured: the part I would look at first
   is its `AssignSideKind` call-result arm, because that is the piece that has
   to distinguish "the name names a routine" from "the name names its result",
   which is exactly the channel this ticket is missing. The rest of that commit
   was the enforcement, which is what went red. Re-measure before reusing any
   of it -- the conformance numbers in the table above predate the channels.
