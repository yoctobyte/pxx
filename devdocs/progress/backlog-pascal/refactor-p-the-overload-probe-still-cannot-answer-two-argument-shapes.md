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

---

## Row 2 re-measured 2026-09-05 (frankO) — the construct is real, the CITATION is not

**`inherited Sort(ItemPtrCompare)` does not appear in fgl.** Real
`/usr/share/fpcsrc/3.2.2/rtl/objpas/fgl.pp` is `{$mode objfpc}` and writes the
`@`:

```
fgl.pp:1051  inherited Sort(@ItemPtrCompare);
fgl.pp:1172  inherited Sort(@ItemPtrCompare);
fgl.pp:1297  inherited Sort(@ItemPtrCompare);
fgl.pp:1531  inherited Sort(FOnKeyPtrCompare);   { a procvar FIELD, not a name }
```

Both shapes compile and run correctly under pxx and match the FPC oracle —
checked directly, not inferred. And FPC **refuses** the bare spelling in
`objfpc` mode anyway (`Incompatible types: got "LongInt" expected
"<procedure variable type...>"`), so the row as written could not have come
from this corpus. Whatever took the fgl rung from 7/7 to 0/7 under a naive
gate, it was not this line. That number is pre-channel and pre-`5dbd56a3c` in
any case; **today's fgl baseline is 7/7, re-measured at HEAD.**

## The construct underneath it WAS real, and it was a different bug

Measured as a matrix rather than a single row, because one cell is not a
finding. `fpc 3.2.2 -Mdelphi` accepts all five:

| spelling | pxx before | fpc |
| --- | --- | --- |
| `v := MyCompare` | ok | ok |
| `FreeRun(MyCompare)` | ok | ok |
| `FreeRun(@MyCompare)` | ok | ok |
| `s.Run(@MyCompare)` | ok | ok |
| **`s.Run(MyCompare)`** | **`undefined variable (MyCompare)`** | ok |

So it is **not** "types as neither a pointer nor the signature" — the gate
never got a chance to abstain, because the name never resolved at all on the
method path. `TryDelphiBareProcArg` was called from the two free-call argument
loops and from NilPy, and from none of the seven method ones.

**Fixed in `8389db919`** by moving the attempt into `ParseArgExpr`, the shared
funnel five of the seven loops pass through — the same place, and for the same
reason, that the bare generator expression was diverted (that function's own
header records the identical free-works/method-fails symptom for
`obj.take(x for x in xs)`).

**What that means for THIS ticket is the part to re-measure, not to assume:**
the argument now yields an `AN_PROCADDR` typed `tyPointer` instead of failing
to resolve, so the probe finally has *an* answer for row 2. Whether it is the
RIGHT answer for a widened `TypesCompatible` gate — `tyPointer` against a
procedural parameter — is exactly what the widening experiment has to show.
Row 2 may be closed as a blocker; it is not closed as a question.

## The gate in this ticket is UNSATISFIABLE ON THIS BOX

`test/pascal-conformance/` holds `pxx.skip` (166 lines) and **zero `.pas`
files**; `library_candidates/` is **empty**; `/usr/share/fpcsrc/3.2.2/tests/`
does not exist. The suite lives at
`library_candidates/fpc-testsuite/tests/test` and is fetched, not vendored.

So the `347/2` half of the gate cannot be measured here at all — and the
harness prints SKIP and exits 0 when the suite is absent, which this ticket
already warns about in its own Gate section. **That warning is now the live
condition, not a hypothetical.** The generic-type-parameter gap (row 1) is the
one the parent attributed to *seven conformance programs and tgeneric9*, so
the corpus that would catch a regression in row 1 is precisely the one that is
missing.

Anyone landing the widening needs `tools/install_lib_candidates.sh` run first,
or the measurement is blind on the axis that broke it last time. fgl (7/7) and
`testmgr --tier quick` are available and are NOT a substitute.

## The seven argument loops, enumerated — because a count in a transcript is not a count

Every parameter-driven loop in the Pascal parsers that reaches an argument
EXPRESSION, at `8389db919`. Five funnel through `ParseArgExpr`; two call
`ParseExpr` directly and therefore did NOT inherit the bare-routine-name fix:

| loop | parses the argument with | via ParseArgExpr? |
| --- | --- | --- |
| `pasparser_call.inc:1994` | `ParseExpr` (2021), `ParseLValueAST` (2026) | **no** |
| `pasparser_call.inc:2711` (the speculative probe) | `ParseArgExpr` (2752) | yes |
| `pasparser_lval.inc:3019` | `ParseArgExpr` (3027), `ParseExpr` (3120) | partly |
| `pasparser_lval.inc:3173` | `ParseArgExpr` (3204) | yes |
| `pasparser_lval.inc:3481` | `ParseArgExpr` (3492) | yes |
| `pasparser_lval.inc:4907` | `ParseArgExpr` (4928) | yes |
| `pasparser_expr.inc:1274` | `ParseArgExpr` (1282), `ParseExpr` (1337) | partly |
| `pasparser_expr.inc:1346` | `ParseArgExpr` (1361) | yes |

(plus the two FREE-call loops in `pasparser_expr.inc:8369` and
`pasparser_stmt.inc:7232`, which already called `TryDelphiBareProcArg`
directly, and `pyparser.inc:49192` for NilPy.)

**Why this table is worth more than the number.** Three of these reach an
argument through `ParseExpr` rather than `ParseArgExpr`, so any future fix
routed through the shared funnel covers five of seven and **silently misses
three** — and the miss presents as "works in most places", which is the
hardest shape to notice. The same applies to the `SetLength expects a string
variable in IR codegen` refusal in
[[bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer]],
which frankH measured as **five per-target twins**
(`ir_codegen386.inc:3284`, `_aarch64:3246`, `_arm32:2613`, `_riscv32:2906`,
`_xtensa:3013`). Two tickets, two duplicated surfaces, and in both cases
"it works" is asserted at whichever arm the test happens to reach.

**And a count is not coverage.** frankH's `LoadFileBuf` case the same day is
the discipline: reading every hit of a constant said the ceiling was live, and
running the OLD binary on an input that should have broken it showed the path
is intercepted by a builtin and never executes under a self-hosted pxx. Before
claiming any of these eight arms is covered, make the current compiler FAIL on
it first.
