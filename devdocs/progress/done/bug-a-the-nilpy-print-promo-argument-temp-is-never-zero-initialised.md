---
slug: bug-a-the-nilpy-print-promo-argument-temp-is-never-zero-initialised
track: A
prio: 80
type: bug
status: done
owner: frankb-8e
created: 2026-09-22
found-by: franks-5b
tags: [nilpy, promotable-int, codegen, refcount, segfault, uninitialised, stack-garbage]
blocked-by: []
summary: "THE NilPy `print()` PROMO ARGUMENT TEMP IS NEVER ZERO-INITIALISED, AND THE CLEANUP PATH RELEASES IT. `main`'s epilogue clears FOUR promo slots (-0x20 -0x30 -0x40 -0x50) while the prologue initialises THREE; the uninitialised one, -0x40, is the print() ARGUMENT TEMP. PXXPromoCopy clears its destination before writing, so PXXPromoClear -- whose body is a managed-string assign releasing the old payload -- runs a release over whatever the PREVIOUS frame left on the stack, and it faults iff those bytes read {tag=1 PROMO_TAG_HEAP, non-static pointer} (observed at that call: tag=0x1, payload=0x338c2665, stale). Emitter is EmitAnsiStrReleaseLocked (ir_codegen.inc:636-665); $40000000 is MSTR_STATIC_RC (defs.inc:122), the saturated refcount a STATIC literal is born with, so the `jae` skips a slot holding the static empty literal -- which is why a warm-up call cures it. ROOT CAUSE, SETTLED 2026-09-22 BY frankb-8e: A COMPILER-SYNTHESISED TEMP TOOK A NAME FOR DEBUGGABILITY AND LOST EVERY GUARANTEE THAT IS KEYED ON NOT HAVING ONE. It satisfies exactly ZERO of FOUR zero-init passes: ir_codegen.inc:13546 and :14717 both require `Name = ''`; the hidden-arg-temp walk (ir_codegen.inc:13487) requires SymIsHiddenArgTemp; and EmitManagedLocalsZeroInit -- the ONE pass with no name filter, which would have caught it -- runs BEFORE the symbol exists. The probe row is `sym=557 name=[__py_parg_3] tk=28 htemp=0 off=-64` with NO store, against `sym=558 name=[] htemp=1 off=-80 STORE`: the named one misses, the unnamed one is covered. FIX IS ONE LINE AT THE MINT SITE, pyparser.inc:25826 -- `SymIsHiddenArgTemp[pargTmp] := True` -- which is what defs.inc:4859 already says that flag means. Not a new mechanism: a flag the site forgot to set. AND IT IS NOT PROMO-SPECIFIC, WHICH MAKES THIS SLUG NARROWER THAN THE DEFECT (kept, because it is cited; read `promo` as where it was CAUGHT, not as its scope): `pargTk` at that site is whatever the argument's type is, so EVERY managed print() argument kind was minted unzeroed. Promo is merely where it turns into a crash, because PXXPromoClear dereferences a stale tag where a nil string handle merely no-ops. DO NOT 'CORRECT' pasparser_expr.inc:381: its guarantee is accurate as written and the mint site does what it promises (frankb-8e, retracting its own earlier report that the temp was not an enumerated symbol -- PXXDBG=a.mlzero is silent about it BY DESIGN, since the ManagedLocalZeroBytes walk at ir_codegen.inc:14710 deliberately skips hidden arg temps to avoid doubling every such store). An earlier version of this summary said the temp had no Sym and told the next seat to fix that comment; both were wrong and the second would have damaged a true sentence. IT IS NOT A FOURTH ARM OF bug-a-managedlocalzerobytes-answers-per-kind-and-has-been-wrong-twice (done/), AND THAT FRAMING IS WITHDRAWN BY THE SEAT THAT WROTE IT (frankz-e5) RATHER THAN REFINED -- an intermediate version of this summary left it 'OPEN' and that is superseded, because leaving a closed question open in a summary sends the next reader to re-measure it. frankb-8e measured that ManagedLocalZeroBytes answers CORRECTLY for every kind involved here, promo included (16), so the pass that consults it is not the pass that fails; the hidden-arg-temp walk is, on a flag the mint site never set. frankz-e5 measured none of that and is retracting on 8e's report. The framing was attractive because the SYMPTOM matched a class NAMED FOR A MECHANISM, and the seat that recognises a symptom is by construction not the seat that measured the mechanism. RENAMED 2026-09-22 from bug-a-two-promotable-int-locals-and-exactly-one-other-local-segfault-at-o2, which named two artefacts and no cause; search that string to land here. BOTH EARLIER FRAMINGS ARE RETIRED AND SO IS THE BISECTION: never-zeroed=[-0x40] is IDENTICAL at -O0/-O1/-O2/-O3 and only the rc differs, so ALL FOUR "clean" rows are LUCK and NO CANDIDATE FIX MAY BE VALIDATED AGAINST ANY OF THEM; two-locals and four-locals carry the same defect at -0x38 and -0x48 and run clean; and with main's source BYTE-IDENTICAL, putting one function call in front of it turns rc=139 into rc=0. The seventeen OptLevel>=2 gates in ir_codegen.inc CANNOT REACH THIS -- no gate creates a defect that is already present at -O0 -- and that bisection is stopped. RETRACTED BY ITS OWN AUTHOR: the "promo-int inline payload dereferenced as a heap bignum pointer" reading is wrong in both halves. rax is STALE STACK, climbing monotonically across sequential runs of ONE binary (0x080a77bf 0x120491cc 0x1cbb96b6 0x2720f0fb 0x33463c57) where a live promo payload could only be 0..3; and the heap tier of a promo int is a MANAGED STRING, not a bignum, so a grep for bignum lowering finds nothing and reads as staleness. WHAT STANDS FROM THE ORIGINAL REPORT, as symptom-selectors rather than as the defect: the nine-line repro segfaults at the shipped default on pin v418 and at HEAD, and `print(str(acc))` runs CLEAN where `print(acc)` segfaults -- which is what names the ARGUMENT TEMP as the uninitialised slot. THE RECYCLING HYPOTHESIS IS DEAD, NOT UNPROVEN: nothing clears that flag because nothing ever SET it. 557 is minted at pyparser.inc:25826, NOT by IRPromoTempSlot -- and the search that had concluded otherwise, `grep 'AllocVar([^)]*tyPromoInt'`, CANNOT reach the real site, because the type arrives there in a VARIABLE (`pargTk := IntToTypeKind(...)`). One hit was read as an exhaustive answer. VERIFIED ON THE EMITTED PROLOGUE rather than on a binary that stopped crashing: before, zeroed=[-0x20,-0x30,-0x50] with CLEARED-BUT-NEVER-ZEROED=[-0x40]; after, zeroed=[-0x20,-0x30,-0x40,-0x50] with CLEARED-BUT-NEVER-ZEROED=[]. Fixedpoint converged, binary 59b5bf39acd1, all four -O levels and every variant rc=0 -- including the ones that were clean BY LUCK, which is the row that matters. Found while benchmarking perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program, whose coarse arm MASKS this by boxing the promo pair to tyVariant -- so narrowing that arm turns working programs into segfaults until this is fixed. ATTRIBUTION: repro and selector table franks-5b; level matrix, IR-identity and gate set frankh-c0; mechanism and all four retirements frankb-8e; summary merged by franks-5b from frankz-e5's rewrite, which measured none of it and corroborated only that pasparser_expr.inc:381 says what 8e reports."
---

# The NilPy `print()` promo argument temp is never zero-initialised, and the cleanup path releases it

## The repro, complete

```python
def main():
    v0 = 0
    acc = 0
    i = 0
    while i < 3:
        acc = acc + 1
        i = i + 1
    print(acc)

main()
```

    ./compiler/pascal26 repro.py out     # default -O, i.e. -O2
    ./out                                # Segmentation fault (core dumped), rc=139

No class, no import, no method call, no library call. `v0` is never read
after its initialiser and never appears in the loop.

## What the compiler inferred

    PXXDBG n.locals main v0  tk=13    { Int64 }
    PXXDBG n.locals main acc tk=28    { tyPromoInt64 }
    PXXDBG n.locals main i   tk=28    { tyPromoInt64 }

`acc` and `i` are promotable ints because they are incremented and could grow;
`v0` cannot, so it stays a plain `Int64`. That inference looks correct. The
defect is downstream of it.

## The trigger, measured rather than reasoned

>  **RETRACTED 2026-09-22 — THIS IS NOT A TRIGGER. Every row below is a real
>  measurement of a quantity that is not the cause.** `frankb-8e`'s disassembly
>  shows the local count only decides which `rbp` offset the `print()` argument
>  temp lands on, and therefore which bytes the PREVIOUS frame left there. **Two
>  locals and four locals carry the IDENTICAL defect at -0x38 and -0x48 and run
>  clean.** The decisive control is not in this table and could not have been,
>  because every variant here changes `main`'s own source: with `main`
>  BYTE-IDENTICAL, `main()` gives rc=139 and `warm(); main()` gives rc=0. Left
>  unedited — it is the evidence for how a reproducible table can map a lottery,
>  and deleting it would hide that.

Holding the two promo-ints fixed and varying the OTHER locals:

| other locals | rc |
| ---: | --- |
| 0 | 0 |
| **1** | **139 (SIGSEGV)** |
| 2 | 0 |
| 3 | 0 |

**A prediction that was wrong and is recorded so nobody re-runs it:** the 2-pass
/ 4-fail / 3-crash shape looked like stack misalignment (3 x 8 = 24 bytes, not
16-aligned), so I predicted odd counts crash and even pass. Measured 1..8 total
locals: only 3 crashes. **It is not an alignment parity.**

Varying the third local's TYPE and POSITION — all still crash:

| variant | third local | rc |
| --- | --- | --- |
| plain first | `v0 = 0` (tk=13) | 139 |
| plain middle | `v0 = 0` | 139 |
| plain last | `v0 = 0` | 139 |
| plain is a string | `v0 = 'q'` (tk=23) | 139 |
| plain is a float | `v0 = 1.5` (tk=19) | 139 |
| **only one promo-int** | `acc` never incremented, so tk=13 | **0** |

So the condition is **two `tyPromoInt64` locals and exactly one other**, and
nothing else about the third local matters.

## Optimisation level

>  **RETRACTED 2026-09-22 — `-O2` IS NOT THE TRIGGER AND THE OTHER THREE ROWS ARE
>  MASKING.** `frankb-8e` probed the slots at every level: zeroed
>  `[-0x20,-0x30,-0x50]`, cleared `[-0x20,-0x30,-0x40,-0x50]`, never-zeroed
>  `[-0x40]` — **identical at -O0, -O1, -O2 and -O3. Only the rc differs.** The
>  missing zero-init exists at every level; the level only changes the emitted
>  code and hence the garbage. **Corollary, and it retires a line of
>  investigation:** no `OptLevel >= 2` gate can be the culprit, so the seventeen
>  `ir_codegen.inc` gates and every halving below them are garbage-lottery rows,
>  not narrowings. `frankh-c0` has been told to stop.

| level | rc |
| --- | --- |
| -O0 | 0 |
| -O1 | 0 |
| **-O2** | **139** |
| -O3 | 0 |
| default (no flag) | **139** |

`-O2` is the proven default, so every ordinary invocation hits it.

## Where it faults

>  **THE INSTRUCTIONS ARE RIGHT AND BOTH STORIES ATTACHED TO THEM ARE WRONG —
>  `franks-5b`, retracting its own reading, 2026-09-22.** Confirmed to the
>  emitter by `frankb-8e`: this is `EmitAnsiStrReleaseLocked`
>  (`ir_codegen.inc:636-665`) and `$40000000` is `MSTR_STATIC_RC`
>  (`defs.inc:122`) — the saturated refcount a STATIC literal is born with, not a
>  numeric threshold — so the `jae` skips a static empty literal, which is why a
>  warm-up call cures the crash.
>
>  **(1) `rax` IS NOT ANY PROMO-INT'S INLINE PAYLOAD. It is stale stack bytes.**
>  Five sequential runs of ONE binary gave `0x080a77bf 0x120491cc 0x1cbb96b6
>  0x2720f0fb 0x33463c57` — monotonic and clock-shaped. My `0x2aa6428c` and 8e's
>  `0x12a2cf7a` are the same slot at different wall-clock times. **A live promo
>  payload in this program could only be 0..3**, and I never asked that question
>  of my own number — one sample of a per-run quantity, read as a value with
>  meaning.
>
>  **(2) "HEAP BIGNUM POINTER" MIS-NAMES THE REPRESENTATION.** The heap tier of a
>  promo int IS a managed string, which is why the release is the AnsiString blob
>  and nothing bignum-specific. A reader grepping for bignum lowering finds
>  nothing and concludes the ticket is stale.

Built `-g -O2`, under gdb:

```
Program received signal SIGSEGV
=> 0x40022a:  cmpq   $0x40000000,-0x10(%rax)
   0x400232:  jae    0x400260
   0x400234:  decq   -0x10(%rax)
   0x400238:  jne    0x400260
rax  0x2aa6428c   (715539084)
```

That is the refcount release sequence — saturation check at `0x40000000`, then
decrement, then skip the free when nonzero. `rax` holds `715539084`, which is a
small integer, not a heap address: **a promo-int's inline payload is being
dereferenced as a bignum pointer.**

## What is NOT established

- **Which pass.** The compiler has no per-pass flags (`--help` lists only
  `-O0..-O3` and `-OO`), so attributing this needs Track A instrumentation.
- **Whether the bug is the release's TAG CHECK or its SLOT INDEX.** Both fit the
  evidence. The same two promo-ints are clean at every other local count, which
  argues against a simply-missing tag check and for something layout-dependent.
- **Whether Pascal or C front ends can reach it.** `tyPromoInt64` is what the
  NilPy frontend infers for a growable integer; no attempt was made to produce
  the same frame from another language.

## Why it had not been found

The shape needs an *unused* extra local beside two loop counters, which is what
a hand-written test rarely has and what real code has constantly. It is also
**masked by boxing**: when
`perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program`'s
coarse arm fires, every method takes variant params and results, the promo-int
pair disappears into `tyVariant`, and the crash goes with it. My first benchmark
for that ticket ran clean *because* it contained a computed `getattr`; deleting
the getattr is what produced the segfault. **Narrowing that arm will unmask this
in programs that currently work.**

## CHEAP DISCRIMINATOR OFFERED, AND ITS PREMISE CHECKED AGAINST THE SOURCE — 2026-09-22

**`frankh-c0` (author of the `--dce`-at-default-`-O2` promotion) offered the one
cheap discriminator so whoever takes this does not start cold: run the repro at
`-O2 --no-dce`.** It did not claim the bug and is not taking it.

Its stated reasoning was that *"clean at -O3"* is a strange row for a
pass-ordering bug **if** DCE is on at `-O2` and off at `-O3`. **That conditional
resolves in the direction that makes the row stranger, not less strange.**
Checked here by READING THE SOURCE — no build was run, and this is a source
reading, not a behavioural measurement:

```
compiler/compiler.pas:2207   if (OptLevel >= 2) and not DceOff and (TargetArch <> TARGET_WASM32) then
                               DceEnabled := True;
compiler/compiler.pas:1040   DceOff := False;                    { initialised }
compiler/compiler.pas:1179   DceOff := True; DceEnabled := False; { --no-dce, the ONLY setter }
compiler/defs.inc:4697       DceOff : Boolean;   { --no-dce: keep every body even at -O3 }
```

`grep -rn DceOff compiler/` returns five hits and they are all accounted for
above plus `compiler.pas:2270` (`EspBareBoot`). **So DCE is ON at `-O2` AND at
`-O3`** — `defs.inc`'s own comment says so in as many words — **and nothing in
the `-O3` path turns it off.**

**THEREFORE "CLEAN AT -O3" IS NOT EXPLAINED BY DCE BEING ABSENT THERE, AND THE
DISCRIMINATOR'S EXPECTATION FLIPS:**

- If `-O2 --no-dce` is **clean**, DCE is implicated only in combination with
  something `-O3` does differently — not on its own, because `-O3` has DCE too.
- If `-O2 --no-dce` still **crashes**, DCE is exonerated outright and the cause
  is a pass that `-O2` runs and `-O3` does not, or one whose behaviour `-O3`
  changes.

**Either way it is one build and it halves the search.** Run it before attributing
anything to a pass.

**Recorded by the coordinator, who did not run it and cannot** — no pxx work in
that seat. Everything above is c0's suggestion plus a source reading; the repro,
the 18 variants and the fault-site reading are `franks-5b`'s and are attributed
to it in this ticket's body. **A second reading of the fault site has been
requested from `frankb-8e`** (Track A, builds), because *"a promo-int's inline
payload dereferenced as a heap bignum pointer"* is 5b's interpretation of the
instruction sequence and register, and 5b flagged it as such rather than as
established.
## 2026-09-22, same day — the trigger is SHARPER and the third condition was missing

The section above is correct and incomplete, and the missing condition changes
where to look. **A promotable int must reach `print` without an explicit
`str()`.** Every variant in the original table happened to end `print(acc)`, so
the print read as scaffolding rather than as part of the trigger.

Holding the frame at three locals, two of them `tyPromoInt64`, and varying only
what is printed:

| what is printed | rc |
| --- | --- |
| `print(acc)` — a promo-int | **139** |
| `print(i)` — the other promo-int | **139** |
| `print(acc + 0)` — a promo-int expression | **139** |
| `print(acc)` then `print(i)` | **139** |
| `print(v0)` — the plain `Int64` | 0 |
| `print(7)` — a literal | 0 |
| `print('done')` — a string | 0 |
| `print(str(acc))` — **the same promo-int, explicitly converted** | 0 |
| no `print` at all (`return acc`) | 0 |

**`print(str(acc))` running clean while `print(acc)` segfaults is the sharpest
row here.** The value, the frame and the local composition are identical; only
the route to a string differs. So the defect is in the IMPLICIT promo-int ->
string conversion on the write path, not in `str()` and not in the loop.

And the promo-int count is **exactly two**, not "at least two":

| promo-ints among 3 locals | rc |
| ---: | --- |
| 1 | 0 |
| **2** | **139** |
| 3 | 0 |

## What the IR shows

`PXXDBG=a.ir:main` on the crashing program, at function exit:

    52: slotaddr a=557 ... tk=17
    53: arg      a=52  ... tk=17
    54: call     a=635 b=53 ... tk=23      { promo-int -> AnsiString }
    55: write    a=54  b=0  c=-2 ival=1 tk=23
    56: writeln  a=55  b=55 ...

`call 635` returns `tk=23`, a **managed AnsiString**, which must be released
after the write. The faulting instruction is a refcount release with a
non-pointer in `rax`. Declared locals in this program are `553 $pyresult`,
`554 v0`, `555 acc`, `556 i`; **`557` is a temporary**, and the composition of
the frame decides which slot that temporary lands in.

**That is a hypothesis with a confirmed prediction, not a conclusion.** The
prediction was stated before testing: *if the faulting release is the
post-print string release, removing the print removes the crash.* It does. What
is still unproven is which slot the release actually targets — the IR above is
pre-backend, and no one has read the emitted release site.

## A confound named rather than resolved

The four clean cases that introduce an intermediate (`s = str(acc)`,
`b = acc`) each add a local **and** route through a named variable, so those two
axes are entangled and those rows cannot separate them. `print(str(acc))` is
the row that does separate them — it keeps the frame at three locals and still
runs clean — which is why it carries the argument above and the others do not.

## Correction to this ticket's own earlier text

The first section says the third local's type does not matter. That is still
true as measured (Int64, AnsiString and Double all segfault) — but every one of
those variants printed a promo-int, so the table was varying one thing while a
second, unnamed condition was held fixed throughout. **The reduction had an
axis nobody enumerated, in a ticket whose own summary warns about a dead local
being one.**

## QUEUED EXPERIMENTS AND THEIR PREDICTIONS, WRITTEN BEFORE RUNNING — franks-5b

Recorded ahead of the measurements deliberately. A prediction written first is a
control; the same sentence written afterwards is a story, and this ticket has
already carried one of each today.

**Not run yet because `lekkerzeilen-7a` has the box for a frame-rate
measurement.** No compiles from this seat until it reports.

### E1 — c0's discriminator: `-O2 --no-dce`

**Prediction: it still CRASHES.** My reading puts the defect in the implicit
promo-int -> AnsiString conversion on the write path, and DCE has no plausible
role in choosing that path. Under e5's source reading (DCE is ON at both `-O2`
and `-O3`), a crash here exonerates DCE outright.

**What would falsify my whole line:** `-O2 --no-dce` coming back CLEAN. That
would mean DCE participates, and the conversion-path reading needs rework
rather than refinement.

### E2 — why is `-O3` clean? The dead-local hypothesis

> **DO NOT RUN THIS AS WRITTEN — the hypothesis below was REFUTED on 2026-09-22
> by `frankh-c0`, see "E1 ANSWERED" further down. The IR is byte-identical at
> `-O1`, `-O2` and `-O3`. **SCOPED, per `frankh-c0` correcting `frankz-e5`:**
> `a.ir:main` dumps the IR *after* IR-level work, so identical-at-all-levels
> rules out an **IR-visible** elimination and does NOT exclude a
> **backend-local** one — a codegen pass noticing `v0` is never read would be
> invisible to that instrument and would still be "-O3 eliminates the dead
> local" in substance. **Probably moot either way:** `frankb-8e` has since shown
> `-O3` is clean for the same reason `warm()` is clean — different code, different
> stack garbage — rather than because anything was eliminated. "Probably" is
> doing real work there; 8e has not tested that specific claim. The question "why is `-O3` clean" is also
> answered in that section and the answer is MASKING, not absence.** Left
> in place unedited, including its prediction, because a prediction written
> before a run is only worth anything if it is still legible after the run
> contradicts it. The trap it records — that `print(v0)` cannot test this,
> because printing a plain `Int64` is itself a clean row — remains true and is
> the part worth carrying forward.

`v0` is written once and never read. **Hypothesis: `-O3` eliminates it**,
leaving two locals — which is a composition measured CLEAN at `-O2`. That would
explain the `-O3` row without any pass-ordering story at all.

**Test, and it has a trap worth stating:** make the third local LIVE and see
whether `-O3` then crashes. The obvious way to do that — `print(v0)` — is
USELESS here, because printing a plain `Int64` is itself one of the clean rows
(condition 3 fails). The third local must be made live **without** changing what
is printed:

```python
    v0 = 1
    acc = 0
    i = 0
    while i < 3:
        acc = acc + v0      # v0 is now read, and still not printed
        i = i + 1
    print(acc)
```

**Prediction: this crashes at `-O2` (unchanged) and ALSO crashes at `-O3`.** If
`-O3` stays clean with a live third local, the dead-local hypothesis is dead and
`-O3` differs for some other reason.

### E3 — the fault site, which is the one thing nobody has read

Disassemble the emitted release after the `writeln` and establish **which slot**
it targets. The IR above is pre-backend; the claim that a promo-int's inline
payload is being dereferenced is an interpretation of `rax` and the instruction
sequence, not a reading of the code. A second opinion is already requested from
`frankb-8e`. **Until someone reads that site, "which slot" is unestablished and
no fix should be written against the guess.**

## E1 ANSWERED 2026-09-22 BY `frankh-c0`: DCE IS EXONERATED IN BOTH DIRECTIONS, AND THE SEARCH NARROWS TO x86-64 CODEGEN

**Run at `fda77c48b8ee` / HEAD `31fe5c049`, on `franks-5b`'s repro verbatim.
`franks-5b` predicted "still crashes" BEFORE it was run and was right.**

```
default        SEGV        -O2            SEGV
-O0            clean       -O2 --no-dce   SEGV
-O1            clean       -O3            clean
--no-dce       SEGV        -O3 --no-dce   clean
```

**`-O2 --no-dce` still crashes and `-O3 --no-dce` is still clean, so DCE neither
causes it at `-O2` nor spares it at `-O3`.** Nobody should spend anything further
on the DCE arm. 5b's level matrix reproduces exactly.

### Three narrowings, and the second one changes how a row already in this ticket must be read

1. **THE IR IS BYTE-IDENTICAL AT `-O1`, `-O2` AND `-O3`** — `PXXDBG=a.ir:main`,
   72 lines, the only difference is the size banner. **So this is purely x86-64
   CODEGEN.** Nothing in `IROptimize` or any IR-level pass is involved, which
   removes a whole layer from the search.

2. **"CLEAN AT `-O3`" IS A MASKING RESULT, NOT AN ABSENCE.** Every gate is
   `OptLevel >= N`, so the ladder is monotonic and `-O3` does everything `-O2`
   does and more. **The defect is almost certainly still emitted at `-O3` and
   landing somewhere harmless** — some `>= 3` pass relocates or elides the bad
   release. The `-O3` row reads as exculpatory and it is not.

3. **THE CULPRIT IS IN THE `-O2` CODEGEN GATES.** Disabling all seventeen
   `OptLevel >= 2` / `< 2` sites in `ir_codegen.inc` at once (rewritten to
   `>= 3`), rebuilding, gives a clean run. c0 is bisecting that set and will send
   the site.

**THIS NARROWS E2, AND THE FIRST VERSION OF THIS PARAGRAPH OVERSTATED IT.
CORRECTED SAME DAY BY `frankh-c0`, WHOSE MEASUREMENT IT WAS.**

I wrote *"an eliminated local would change the IR, therefore E2 is refuted
outright."* **That is stronger than the instrument supports.** `PXXDBG=a.ir:main`
dumps the IR for `main` AFTER whatever IR-level work runs. Identical at all three
levels means **no IR-level pass distinguishes them**, so an **IR-visible**
dead-local elimination is out. **It does not exclude a BACKEND-LOCAL elimination
that never reaches the IR dump** — a codegen pass noticing `v0` is never read and
skipping its slot or its release would be invisible to that instrument and would
still be *"-O3 eliminates the dead local"* in substance.

**So: E2's mechanism is out IN ITS IR FORM and its question survives in a BACKEND
form. Do not drop the line of inquiry.** The error was the coordinator's — a
quantifier asserted past what the probe enumerates, in the field a dispatched seat
reads, which is this file's own most-repeated failure.

**The trap E2 recorded gets cheaper either way:** since the three levels share IR,
a fixture that makes `v0` live can be checked for having changed the IR **at
all** — one dump, rather than a reasoned argument about whether the change was
the intended one.

**E3 IS UNCHANGED AND STILL THE HARDEST HOLD.** The inline-payload reading remains
5b's interpretation of `rax` plus four instructions. The suspect has now moved
twice — off the loop and frame layout by the `print(str(acc))` row, off DCE and
off the IR entirely by this one — **so no fix may be written against that reading
until someone disassembles the emitted release site.** Requested from `frankb-8e`.

**Scope, recorded because it is how this stayed clean:** c0 ran a discriminator and
is running a bisect; it has NOT taken the ticket. `franks-5b` owns it. c0 offered
to hand the bisect over mid-flight if either 5b or 8e wants it.

**Instrument note from c0, worth having beside the numbers:** its first grep for
the `-O2` gates filtered out the `and`-form conditions and returned **4 sites
where there are 17** — a pattern written for `if OptLevel >= 2 then` is silent
about `(OptLevel >= 2) and (...)`, **and the short list looked complete.** The
seventeen-site result above is from the corrected set.

### BISECT STATE — RELABELLED 2026-09-22: THESE ARE GARBAGE-LOTTERY ROWS, NOT NARROWINGS

**READ THIS BEFORE THE NUMBERS BELOW.** They were recorded as a localisation and
they are not one. `frankb-8e`'s disassembly (see the E3 section) shows
`never-zeroed=[-0x40]` is present at **`-O0` too**, so **no `OptLevel >= 2` gate
creates this defect and none of them can be the culprit.** What toggling a gate
does is change the emitted code, which changes the frame layout and what the
previous frame left behind — **it re-rolls the garbage.**

**So "the culprit is in the first eight" is exactly as informative as "two locals
clean, three locals SEGV": a real, reproducible measurement of a quantity that is
not the cause.** `franks-5b` asked for this relabelling explicitly, so that the
next reader does not treat it as live and spend a day inside `ir_codegen.inc`.

**THE CONTROL THAT KILLS EVERY FLAG-BISECT, and it is not a codegen experiment at
all:** with `main`'s source **byte-identical**, `main()` gives rc=139 and
`warm(); main()` gives rc=0, where `warm()` is one function with one string local.
Nothing about the compiler changed. **The same binary gives both answers**, so no
bisect over compiler flags can survive it.

**The runs themselves were competent and the method was right** — c0 reached
halving before anyone suggested it, and halving is what would have found a real
single-gate cause in ~5 rebuilds. The rows are preserved below as history, marked
for what they measure.

#### Historical rows — `frankh-c0`, 2026-09-22

Recorded here because the bisect yielded the box to an owner-cleared display
window and **a paused bisect whose state lives only in a peer's context is a
restart**, not a pause.

Seventeen candidate `OptLevel >= 2` / `< 2` sites in `compiler/ir_codegen.inc`:

```
all seventeen disabled                                  -> clean
first eight: 5852 8192 8804 8813 9211 9250 9298 9514    -> clean
second nine                                             -> still SEGV
```

**So the culprit is in the FIRST EIGHT** and two halvings remain. The in-flight
command was testing `5852 8192 8804 8813` against `9211 9250 9298 9514`.

**Candidate set by kind, c0's characterisation and deliberately not reasoned
further:** the statement-level and call-path gates — a static-literal handle pass,
an indirect-call last-argument collapse, and two array-index forms. **If it lands
on the last-argument collapse that would bear directly on the `print(str(acc))`
row**, since that row is a one-argument call with a conversion in argument
position. c0 stopped reasoning there on purpose: *"this is exactly the shape where
a prediction written before the measurement gets pinned instead of the tree."*

**Safety note that belongs with the state, not with the coordination:** that script
patches a tracked file and restores it **at the end**, so killing it mid-run leaves
a modified `ir_codegen.inc` **and** a `compiler/pascal26` built from it — and the
binary is untracked, so `git status` shows only the source edit. c0 is verifying
the tree is clean before stopping and will say so. Anyone resuming this should
check both.

## E3 ANSWERED 2026-09-22 BY `frankb-8e` — AND IT RETIRES BOTH FRAMINGS IN THE SLUG, THE BISECTION, AND ONE OF ITS OWN EARLIER CLAIMS

**This is the disassembly this ticket said no fix could be written without.**
Recorded by the coordinator, who measured none of it. Every number below is 8e's,
with `--map` resolving every address.

### The mechanism

**`main`'s epilogue clears FOUR promo slots; the prologue initialises THREE. The
uninitialised one is the `print()` ARGUMENT TEMP.** The fault is the
`AnsiStrRelease` blob (`EmitAnsiStrReleaseLocked`, `ir_codegen.inc:654`), reached
from `PXXPromoClear`, whose body is a managed-**string** assign releasing the old
payload. `PXXPromoCopy` clears its destination before writing it. gdb at that
call: `tag=0x1` (`PROMO_TAG_HEAP`), `payload=0x338c2665`, stale.

**`compiler/pasparser_expr.inc:381` ALREADY DESCRIBES THIS FAILURE** — *"a local
left unwritten on the executed path was cleared with stale stack bytes, and bytes
that happened to read `{1, <a live pointer>}` freed a block nobody had freed"* —
**and asserts the temps satisfy `PXXPromoClear`'s own precondition through
`SymIsHiddenArgTemp`'s prologue zero. That is false for this one.** Corroborated
here by reading that file; it is the only thing in this section the coordinator
checked.

### Three retirements, and none of them is a refinement

1. **NOT `-O2`.** `never-zeroed=[-0x40]` is **IDENTICAL at `-O0`, `-O1`, `-O2` and
   `-O3`** — only the rc differs. **All four "clean" rows are LUCK.** The
   coordinator's "clean at -O3 is masking, not absence" call was right and
   generalises to *every* clean level. **No candidate fix may be validated against
   any row in that matrix.**
2. **NOT THE LOCAL COUNT.** `two_locals` and `four_locals` carry the same defect at
   `-0x38` and `-0x48` and run clean. **With `main`'s source byte-identical,
   putting one function call in front of it turns rc=139 into rc=0** — a slot left
   by an earlier `PXXPromoClear` holds the STATIC EMPTY LITERAL and the saturation
   guard skips it.
3. **THE SEVENTEEN `OptLevel >= 2` GATES CANNOT REACH THIS.** That bisection is
   stopped; 8e messaged `frankh-c0` directly. The 17-site *observation* was real —
   disabling them all does run clean — which is exactly how a true measurement
   points at the wrong mechanism.

### And a retraction by its own author

**8e's earlier report that the fault dereferences a promo payload is WRONG.**
`rax` varies per run and **climbs monotonically across sequential runs**, so it is
**stale stack, not any live value** — which is also why 5b's `rax` and 8e's
differ. Self-reported before anyone built on it.

### The suspect has now moved four times

Off the loop and frame layout (`print(str(acc))`), off DCE (`-O2 --no-dce`), off
the IR entirely (`a.ir:main` identity), and now off the optimisation level and the
local count together. **Each move invalidated a fix someone could plausibly have
written in between, and the last one invalidates a per-level fix anyone could have
written this afternoon.** This is the argument for E3 having gated the fix, and it
is worth reading before the next ticket where a bisected site arrives without a
disassembly.

### Routing — recorded, not decided

`frankb-8e` holds the mechanism and has asked `frankh-c0` directly whether it
wants the fix or is already at the mint site, offering its candidates
(`ir.inc:5984`, `ir.inc:14261`, `pyparser.inc:61658`). `franks-5b` filed the
ticket and owns it but is off the box at `lekkerzeilen-7a`'s request. **The
coordinator does not dispatch and has not.**

## Mint site found — and it is flagged, so `:381` is NOT the false part (frankb-8e, 2026-09-22)

**Banking this before the fix, because it corrects a sentence in this ticket's own
summary and a claim I sent to two seats.**

**`ir.inc:1880 IRPromoTempSlot` is the only producer of a promo temp in the
compiler** — `grep 'AllocVar([^)]*tyPromoInt' compiler/*.inc` returns exactly one
hit, `ir.inc:1883`, inside it — and it sets the flag two lines later:

```pascal
  tmpSym := AllocVar('', tyPromoInt64);
  { First-touch init: ONE prologue zero via the hidden-arg-temp machinery ... }
  SymIsHiddenArgTemp[tmpSym] := True;
```

So the temp IS flagged at birth, and `pasparser_expr.inc:381`'s assertion that
these temps are covered by `SymIsHiddenArgTemp`'s prologue zero **describes the
mint site accurately.** The summary above calls that assertion FALSE; that was my
report and it is too strong. **Do not "correct" the comment at `:381` — it is
true about the thing it is talking about.** What fails is downstream of it.

### What is actually open, and it is narrower than anything in this ticket so far

From `PXXDBG=a.ir:main` (which also retires my "the temp is not an enumerated
symbol" claim outright — instruction 47 is `slotaddr a=557`):

| sym | what it is | slot | prologue emits |
| --- | --- | --- | --- |
| 557 | the `PXXPromoCopy` destination — the `print()` argument temp | `-0x40` | **nothing** |
| 558 | the literal-`3` temp for `i < 3` | `-0x50` | `movq $0x0,-0x50(%rbp)` |

**Both are minted by `IRPromoTempSlot`, both are therefore flagged, both are
`skLocal`** (`AllocVar` takes `skLocal` whenever `CurProc >= 0`,
`symtab.inc:145-148`, and a `skGlobal` temp would be in BSS rather than at
`rbp-0x40`), **both are inside `main`'s scope, and they are adjacent indices.**
The hidden-arg-temp prologue walk (`ir_codegen.inc:13487`) fired **once**.

So something between *flag set at mint* and *flag read at emit* drops 557 and
keeps 558. That is the whole remaining question.

**One hypothesis with a mechanism, NOT a finding, and recorded as such:** symbol
slots are recycled across procs (`symtab.inc:5876`, `SymCount := keepTo`), and
`AllocVar` resets `SymIsHiddenArgTemp[SymCount] := False` for the slot it hands
out — so a later proc reusing index 557 would clear `main`'s flag before `main`'s
codegen reads it. **Against it:** `DbgRecordVar`'s own comment says slot capture
must run while the proc's scope is live, which implies codegen does. I have not
watched either happen and the next step is a probe (`PXXDBG=a.htemp`) printing
every symbol that walk iterates with its flag, kind and offset.

### Two instrument failures of mine, both the same shape, recorded so the next reader does not inherit them

1. **`PXXDBG=a.mlzero` is silent about this temp BY DESIGN**, and I read the
   silence as absence. The walk that consults `ManagedLocalZeroBytes`
   (`ir_codegen.inc:14710`) explicitly SKIPS `SymIsHiddenArgTemp` entries — its
   own comment gives the reason (doing them there too doubled every such store,
   ~112 KB on the compiler's own code). **A probe that is silent by construction
   read as a probe reporting a negative.**
2. **A disassembly probe answered `zeroed=[]` and every call count `0` for seven
   rows**, because pxx writes no ELF section headers without `-g`, so `objdump`
   had no section containing the address and exited 0 with no output. Written up
   at `8dca96acb`, `debugging-playbook.md`.

**Both are the silent-zero shape, and I hit the second while writing up the
first.** Knowing the rule did not fire it; in each case what caught it was a
number from a *different source* disagreeing — the hand disassembly for (2), and
the IR dump for (1).

### Binary provenance for every number above

Measurements were taken with two different compilers and agree on the load-bearing
row: `fda77c48b8ee` (pin v418, tree `14760b8e0`) and `9839a38adf35` (a local build
carrying an experimental arm that never fired, since reverted). **`-0x40` is
cleared-but-never-zeroed under both.** The `a.ir:main` and `a.mlzero` dumps above
were taken with `9839a38adf35`.


## IN FLIGHT WITH `frankb-8e` AS OF 2026-09-22 — recorded by `frankh-c0`, who did NOT take it

`owner:` set here on 8e's own statement, not inferred: *"Say if you want the fix
or if you are already at the mint site — I do not want us both writing it."* I
replied that the fix is 8e's and that I am nowhere near the mint site. Recording
it because `next` handed me this ticket at effective p95 with `owner: ""`, so the
next seat to ask for work gets dispatched straight into a fix somebody is already
writing — and neither diff would conflict, which is the collision git cannot see.

**Falsifiable rather than authoritative:** if 8e is not on it, clear the field. It
is attribution, not a lock.

**What 8e has already ruled out, so nobody repeats it:** a promo arm added to the
per-caller subset at `ir_codegen.inc:13508` does NOT fire, and is the wrong shape
anyway — the shared pass at `14710` using `ManagedLocalZeroBytes` already answers
16 for promo. Neither reaches the temp, and 8e reverted that edit. **THE REASON GIVEN HERE WAS
WRONG AND IS RETRACTED BY ITS AUTHOR — corrected at the point a reader meets it,
not in the section below.** 8e reported the temp as *"not an enumerated symbol at
all"* from `PXXDBG=n.locals` listing three locals and `a.mlzero` never being asked
about the `-0x40` slot. It IS an ordinary symbol (`a.ir:main` instruction 47 is
`slotaddr a=557`). `a.mlzero` is silent about it **by design** — the `14710` walk
skips `SymIsHiddenArgTemp` entries and its own comment says why — and that silence
was read as a negative. The real reason those passes miss it is its NAME; see the
FIXED section below.

**And do not validate a candidate against any `-O` level's row** — all four are
luck (see the playbook entry on a bisection predicate that is not a function of
the search space). Validate against the emitted prologue: does it now initialise
the slot.
## FIXED — the temp is `__py_parg_N` and it fell through every zero-init pass on its NAME (frankb-8e, 2026-09-22)

**`PXXDBG=a.htemp`, the probe this needed, settled it in one build. The rows:**

```
RANGE proc=main scopebase=553 symcount=559
sym=553 in=1 name=[$pyresult]    tk=1  kind=0 htemp=0 off=-4
sym=554 in=1 name=[v0]           tk=13 kind=0 htemp=0 off=-16
sym=555 in=1 name=[acc]          tk=28 kind=0 htemp=0 off=-32
sym=556 in=1 name=[i]            tk=28 kind=0 htemp=0 off=-48
sym=557 in=1 name=[__py_parg_3]  tk=28 kind=0 htemp=0 off=-64     <- no STORE
sym=558 in=1 name=[]             tk=28 kind=0 htemp=1 off=-80
STORE sym=558 off=-80 form=qword                                  <- the control
```

**The answer was a FOURTH outcome none of the three of us enumerated**, and every
prediction on this ticket — including mine — was wrong about the mechanism:

- **`in=1`.** The walk's own bounds are 553..558, so 557 was visited. Not a range
  or scope defect.
- **`htemp=0`.** The flag was never set — so it was never CLEARED either, and the
  symbol-slot-recycling hypothesis I recorded above is **dead, not merely
  unproven.** Nothing clears this flag; nothing ever set it.
- **`name=[__py_parg_3]`.** It is not an unnamed temp. **That is the whole
  defect.**

### Why my "only one `AllocVar` of a promo type" was a grep artefact

`grep 'AllocVar([^)]*tyPromoInt'` returned exactly one hit and I reported the mint
site as settled. The real site is `pyparser.inc:25826`:

```pascal
  pargTk := IntToTypeKind(ASTTk[CurASTNode]);     { a VARIABLE }
  ...
  pargTmp := AllocVar(PyHiddenName('parg'), pargTk);
```

**The type arrives in a variable, so no grep for the type NAME can ever reach it**,
and the name is synthesised by `PyHiddenName`. This is CLAUDE.md's "grep for the
OTHER SPELLING'S HANDLER, not for the feature" — and note the failure was silent
and confident: one hit reads as an exhaustive answer.

### Four passes, four misses, and the reason is the same in three of them

| pass | filter | why it missed `__py_parg_3` |
| --- | --- | --- |
| `EmitManagedLocalsZeroInit` (`pasparser_expr.inc:471`) | `Kind = skLocal`, **no name filter** | would have covered it — it simply **runs before this symbol exists** |
| hidden-arg-temp walk (`ir_codegen.inc:13512`) | `SymIsHiddenArgTemp` | flag never set at the mint site |
| unnamed safety net (`ir_codegen.inc:13546`) | `Name = ''` | it has a name |
| for-in/COM temp pass (`ir_codegen.inc:14717`) | `Name = ''` and not flagged | it has a name |

**A compiler-synthesised temp acquired a NAME for debuggability and lost every
guarantee that is keyed on not having one.** `EmitManagedLocalsZeroInit` is the one
pass with no name filter and it is the one that runs too early — so the symbol
satisfied exactly zero of the four.

### The fix

One line at the mint site, `pyparser.inc:25826`:

```pascal
  SymIsHiddenArgTemp[pargTmp] := True;
```

`SymIsHiddenArgTemp`'s own definition in `defs.inc:4859` is *"compiler-synthesised
owning managed local ... allocated after the parser's prologue zero-init pass, so
codegen nil-inits it before the body"* — which describes this temp exactly. It was
not a new mechanism; it was a flag the site forgot to set. **This is why
`pasparser_expr.inc:381`'s guarantee must still NOT be "corrected": it is accurate
about the temps that carry the flag, and the bug was a temp that did not.**

### Verified on the EMITTED PROLOGUE, not on a binary that stopped crashing

`frankh-c0`'s acceptance condition, and it is the right one here because every
"clean" row on this ticket was luck:

```
before: zeroed=[-0x20,-0x30,-0x50]        CLEARED-BUT-NEVER-ZEROED=[-0x40]
after:  zeroed=[-0x20,-0x30,-0x40,-0x50]  CLEARED-BUT-NEVER-ZEROED=[]
after:  a.htemp -> sym=557 htemp=1, STORE sym=557 off=-64 form=qword
```

Runtime rows, all previously-crashing shapes now correct — but read these as
corroboration, not as the proof:

    -O0/-O1/-O2/-O3/default   rc=0 out=3        (was 139 at -O2 and default)
    pre_none pre_print pre_twice called_twice   rc=0   (all were 139)
    two_locals four_locals pre_call dirty2      rc=0   (were clean by luck)
    print(str, float, bignum, obj field)        rc=0   correct output

The bignum row matters: `12345678901234567890` is a HEAP-tier promo, so it
exercises the tag-1 path the crash was mis-taking.

### Scope — this was never promo-specific

`pargTk` is whatever the argument's type is, so **every managed `print()` argument
kind was minted unzeroed**: `tyAnsiString`, `tyClass`, `tyVariant` and promo alike.
Promo is simply where it was caught, because `PXXPromoClear` dereferences a
stale tag where a nil string handle merely no-ops. The single flag fixes all of
them, and the 8-byte store the walk emits is the established contract for a promo
slot (tag word reads `PROMO_TAG_INLINE`) — the same one `IRPromoTempSlot` relies
on for its own temps.

**Residual, stated rather than assumed:** the walk's non-record arm stores 8 bytes
regardless of kind, which fully covers a handle, a pointer and a promo tag, but is
half of a `tyVariant` slot. Variants reaching this path are now zeroed where before
they were not, so this is strictly an improvement — but it is not a claim that the
variant case is complete, and I have not constructed one that proves it either way.

## Log
- 2026-09-22 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 05e56ab32.
