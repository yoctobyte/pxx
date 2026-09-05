---
slug: refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes
title: "Two argument shapes no side channel answers, so the method gate still abstains where the free path decides"
track: P
prio: 55
type: refactor
blocked-by: []
status: done
owner: "frank-optimize"
created: 2026-09-05
summary: "RESOLVED. The widened gate now costs ZERO rows on all three axes -- Pascal corpus 1581/286 unchanged (row-level diff, not just totals), conformance 381 pass / 2 fail with an identical failure list, fgl 7/7 -- and it refuses five programs fpc 3.2.2 also refuses that pxx silently accepted. The two blocking shapes were NEITHER of the ticket's named rows. One was a real pre-existing bug in a different file: the implicit Self shift forgot `puntyped`, so a method's untyped-param flag sat one slot left of its parameter (fixed in a916c48bf). The other was the implicit class->interface coercion, which MatchProcCall reaches only by falling through to its phase 2c -- a rewound probe never falls through, so the fix is MatchParamAccepted, the UNION of what the phases accept, spelled once and called from both. Row 1 (generic type parameter) fires zero times against the real 1447-program conformance corpus."
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
   argument position", not "the assignment".

   **CORRECTED 2026-09-05 by frank-optimize's measurement, and the correction
   changes the REMEDY, not the population.** I wrote above that the machinery
   exists on the Delphi side and the answer is missing outside it, which reads
   as "make the bare name bind its address everywhere". That is wrong. FPC in
   DEFAULT mode refuses all three:

   ```
   f := G       Incompatible types: got "SmallInt" expected "<procedure variable type...>"
   Use(G)       Incompatible type for arg no. 1: Got "SmallInt"
   Use(G) proc  Incompatible type for arg no. 1: Got "untyped"
   ```

   So reading the bare name as a call is FPC's behaviour too, and the type
   error is the CORRECT outcome outside Delphi mode. The first two faces are a
   missing DIAGNOSTIC that we turn into a crash, not a missing address-binding
   channel -- which is what
   [[bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode]]
   said in its own summary all along ("erroring like FPC is the fix"). Making
   them bind would have us accepting in objfpc mode what FPC deliberately
   refuses, and the mode directive is the thing that is supposed to decide it.
   Refusing is also the much smaller job.

   The three-face split is still the right scoping -- it is what led to the
   real defect in the ARGUMENT position, which frank-optimize landed as
   `8389db919`: `TryDelphiBareProcArg` was called from the two free-call
   argument loops and from NilPy and from NONE of the seven method ones, so
   `s.Run(MyCompare)` never resolved the name at all and the gate never got to
   abstain. One cell of a five-cell matrix, found by varying the SPELLING
   rather than chasing the crash.

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


## The gate cannot fail — stated in CLAUDE.md's own words, at frankB's suggestion

**"A GUARD THAT CANNOT FAIL IS NOT A GUARD, AND IT PRINTS PASS."** That is this
ticket's Gate section today, exactly:

- `test/pascal-conformance/` contains `pxx.skip` (166 lines) and **zero `.pas`
  files**.
- `library_candidates/` is **empty**; `/usr/share/fpcsrc/3.2.2/tests/` does not
  exist. The suite is fetched (`tools/install_lib_candidates.sh`), not vendored.
- `tools/run_pascal_conformance.sh` prints SKIP and **exits 0** when the suite
  is absent.

So the conformance half of the gate returns success without having run, on the
one axis the widening is known to have broken — the parent attributed row 1 to
*seven conformance programs and tgeneric9*. Anyone reading a green here would
be reading a guard that cannot come out false.

**fgl 7/7 and `testmgr --tier quick` are NOT a substitute and must not be
reported as one.** They are the axis that did not break last time. Quoting two
greens taken where the failure was never going to appear is corroboration only
as wide as the layer it was taken at.

**If the widening is landed, it must be landed saying which axis is unmeasured**
and that the number required is unobtainable on this box — not by reporting the
two greens that are obtainable.

## Unowned residual: what actually took the fgl rung 7/7 -> 0/7

Row 2 was the stated explanation and row 2 does not exist in fgl. So the
regression the parent measured under a naive `TypesCompatible` gate is
**unexplained, not explained**, and nothing currently owns finding out. It may
be row 1, it may be a shape nobody has named, and it may be stale — the number
predates the channels and predates `5dbd56a3c`. Whoever attempts the widening
inherits this question and should expect the rung to move for a reason not
written down anywhere.


---

## The widening was RUN, 2026-09-06 (frankO) — and it corrects my own correction above

I wrote above that *"whatever took the fgl rung from 7/7 to 0/7 under a naive
gate, it was not this line."* **That was wrong.** It is that line. Row 2 named
the right location and mis-transcribed the spelling as a bare name; I then
over-corrected from the mis-transcription to "the citation is irrelevant".
Both errors were about the SPELLING — the location was right the whole time,
and one run settled what reading the source text did not.

### What was run

The allowlist's two narrowing lines deleted, so the `nCand = 1` gate runs the
full check:

```pascal
if not ((argTk[j] = tyPointer) or (argTk[j] = tyClass)) then continue;   { deleted }
if not (TypeIsOrdinal(...) or ... tyFixedString) then continue;          { deleted }
if not TypesCompatible(Procs[pi].Params[pj].TypeKind, argTk[j]) then ok := False;
```

Built (`converged`, sha256 `0ae9c53c6339`), measured, reverted with
`git checkout --`, rebuilt back to `f2f11cd439e7`, fgl re-confirmed 7/7.

### Result

| measurement | before (`f2f11cd439e7`) | widened (`0ae9c53c6339`) |
| --- | --- | --- |
| Pascal corpus, 1864 programs | 1578 compile / 286 refuse | 1576 / 288 |
| fgl rung | 7/7 | **3/7** |

**Discrimination control, because a 4-row diff is exactly what a blind
instrument also produces.** The same census run against the pinned compiler
(`fe1e9c37d322`) differs from HEAD on **48 rows**, including
`test_delphi_bare_proc_method_arg` (0 at HEAD, 1 at pin). So the census can see
a difference; the 4 rows are 4 real rows, not an instrument that never reached
the arm.

### The three regressions, and two of them are ONE shape

```
fgl.pp:1051, :1172   inherited Sort(@ItemPtrCompare);
                     -> TFPSListCompareFunc = function(Key1, Key2: Pointer): Integer OF OBJECT
test_fpc_compat_batch2:138   l.UseCallback(@...)
                     -> the row is literally named 'methodptr-param-arg-and-call'
test_getinterface_guid_b257:81   h.QI(gFoo...)   -> a GUID constant
```

**So the shape with no channel is `@Routine` (or `@Obj.Method`) reaching a
parameter whose type is a METHOD POINTER (`of object`).** The argument types
`tyPointer`; the parameter is a procedural-of-object type; `TypesCompatible`
says no — correctly about kinds and wrongly about the program. That is a real
missing channel and it is what row 2 was pointing at all along. It is simply
not "a bare routine name", and the bare spelling is refused by FPC in objfpc
mode regardless.

**Row 1 did not fire.** The generic-type-parameter gap, which the parent
attributed to seven conformance programs and tgeneric9, produced **zero**
regressions in the corpus available here. That is not evidence it is fixed —
the Pascal conformance directory holds zero program files on this box, so the
programs that would exercise it were never run. Absence measured where the
population is absent.

### What this ticket needs now

1. A channel answering **"argument j is a routine or method ADDRESS"**, filled
   where `AN_PROCADDR` is built, so the check can be told the argument is
   address-shaped rather than being handed a bare `tyPointer`. Two of the three
   regressions go away with that alone.
2. The GUID row triaged separately — a different shape, one instance.
3. Row 1 re-measured **only** on a box with the conformance suite fetched.
   Nothing about it can be concluded here in either direction.

The widening is NOT ready to land, and the reason is now specific rather than
historical: it costs the fgl rung four drivers at a line that exists.


---

## Conformance MEASURED, 2026-09-06 (frankO) — the widening is free on that axis

The suite is fetchable and was simply not on this box. `tools/install_lib_candidates.sh
fpc-testsuite` brings 1447 programs, pinned to the release_3_2_2 tag, into
gitignored `library_candidates/`. `test/pascal-conformance/` holds only
`pxx.skip` and is the skip list, **not** the corpus — reading it as the corpus
is what produced the "gate cannot fail" note above, and that note was right
about the consequence and wrong about the remedy: nothing was missing from the
repo, the fetch had never been run here.

### Result — same sources both arms, differing ONLY by the widening

| | baseline `ce3cbc03f79a` | widened `80d91c4a6605` |
| --- | --- | --- |
| pascal conformance (550 curated) | **381 pass / 3 fail** | **381 pass / 3 fail** |
| failures | tdefault8, tgeneric4, tgenfunc14 | tdefault8, tgeneric4, tgenfunc14 |

**Zero conformance regressions.** The same three rows fail on both sides.

**Row 1 is empirically closed.** The parent attributed the generic-type-parameter
gap to *"7 conformance programs and tgeneric9"* and measured `346 -> 338/8`.
Today the widening costs **nothing** there — the seven argument-match channels
added since have absorbed it. `346 -> 338/8` is not merely stale as a baseline,
it is stale as a *diagnosis*: the shape it described no longer regresses.

### A measurement error of mine, recorded because the artefact is instructive

My first conformance pair read `382/2 -> 381/3` and I nearly reported
`tdefault8.pp` as the widening's one remaining cost. It is not: **tdefault8
fails at HEAD with the widening reverted.** The baseline arm had been measured
with a binary built before a `sync.sh` pulled two `compiler/` commits, and I did
not rebuild — the exact failure CLAUDE.md names ("rebuild after any sync
touching `compiler/**` before you measure"). The two arms differed by my
experiment *and* by someone else's commits, and the difference was attributed
entirely to mine.

The tell was that the "regression" made no sense for the mechanism: a gate that
refuses on argument/parameter compatibility has no way to produce
`unknown type: TRange`. **A regression whose error message does not fit the
mechanism under test is the signature of a contaminated baseline**, and it is
worth more than the sha check that would also have caught it, because it fires
without your having to suspect anything.

`tdefault8` is a real regression, just not this one's — narrowed to a two-commit
window, reported to its author, and tracked separately.

### What actually blocks the widening now, and it is ONE channel

| cost | rows | shape |
| --- | --- | --- |
| fgl rung 7/7 -> 3/7 | fgl.pp:1051, :1172 | `@Routine` -> METHOD POINTER parameter |
| corpus 1578 -> 1576 | test_fpc_compat_batch2:138 | same shape (`methodptr-param-arg-and-call`) |
| | test_getinterface_guid_b257:81 | GUID constant |
| conformance | — | **none** |

So the ticket's two named gaps have become **one**, and it is neither of them
as written: a channel answering *"argument j is a routine or method ADDRESS"*,
filled where `AN_PROCADDR` is built. Everything else the widening would cost is
one GUID row.


---

## RESOLVED, 2026-09-06 (frankO) — and neither named row was what blocked it

### The measurement, all three axes, both arms built from the same tree

Baseline `98032c2f69fc` and widened `9a9499803ad9`, both at commit `a916c48bf`,
each rebuilt after the last sync that touched `compiler/`:

| axis | baseline | widened |
| --- | --- | --- |
| Pascal corpus, 1867 files | 1581 compile / 286 refuse | **1581 / 286** |
| ...row-level diff | — | **0 rows differ** |
| conformance (550 curated) | 381 pass / 2 fail | **381 / 2**, identical list |
| fgl rung | 7/7 | **7/7** |

**Discrimination control, because a zero-row diff is what a blind instrument
also prints:** the same census against the pinned compiler differs from the
baseline on **56 rows** — and one of them is
`test_method_untyped_param_self_shift.pas`, a row whose truth this session
established independently (1 at the pin, 0 at HEAD). The census can see a
difference, and the zero is a real zero.

### What it buys

Five programs **fpc 3.2.2 refuses** and pxx accepted with no diagnostic at all,
each a single-candidate method call: a string literal for an `Integer`
parameter (three spellings — class, interface, and with an untyped parameter
present), and a record for an `Integer` parameter. The identical FREE procedure
refused every one of them. That asymmetry is what this ticket was filed about.

### The two blockers, and why the ticket named neither

**1. `puntyped` was not shifted with the implicit Self** —
`bug-p-the-self-shift-forgets-puntyped-so-a-method-param-is-mislabelled`, fixed
in `a916c48bf`. A pre-existing bug in `pasparser_proc.inc` /
`pasparser_decl.inc`, invisible until the widened gate became the first thing
ever to ask a METHOD parameter whether it was untyped. It was reported here as
"a GUID constant at `test_getinterface_guid_b257:81`" — **that was wrong**;
narrowing the row to a repro showed `constref IID: TGuid` accepts fine on its
own and the refusal was on the untyped `out Obj` beside it.

**2. The implicit class->interface coercion.** `MatchProcCall` grants it in
**phase 2c**, a later phase the free path reaches by falling through. The
speculative method probe has already rewound its token stream and gets exactly
one question, so it never arrives. This is the same asymmetry as
`MatchCallDelphiProcAddr`'s `AN_PROCADDR` retry, one layer up. Reported here as
fgl's generic `Add(Item: Pointer)` competing with `Add(const Item: T)` — also
wrong: with an interface *variable* the call binds fine; it is the class
instance `TFoo.Create(3)` that needs the coercion.

Fix: `MatchParamAccepted` — the UNION of what the phases accept, spelled once
in `symtab.inc` and called from both phase 2c and the probe. **Deliberately not
folded into `MatchParamCompatible`**: widening that would let phase 2a accept a
class->interface argument that today only 2c accepts, which changes *which*
overload wins, not merely whether one does. The phases keep their order; only
the probe, which has no phases, is given the union.

### The `MatchArgProcAddr` channel

Still present and still load-bearing: `@Routine` / `@Obj.Method` reaching a
method-pointer parameter (fgl.pp:1051, :1172). Without it the rung was 6/7 with
everything else in place.

### Corrections to this ticket's own body, kept because the pattern repeats

Three characterisations above are wrong and each was wrong the same way — a
shape named from **reading source** rather than from **reducing to a repro**.
The location was right every time; the mechanism was not. `r2a`/`r2c` (GUID
alone) and `r1a` (interface variable) are four-line programs, and each took
under a minute to falsify the reading it replaced.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
