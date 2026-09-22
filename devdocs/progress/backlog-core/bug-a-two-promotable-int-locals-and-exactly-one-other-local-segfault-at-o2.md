---
slug: bug-a-two-promotable-int-locals-and-exactly-one-other-local-segfault-at-o2
track: A
prio: 80
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: franks-5b
tags: [nilpy, promotable-int, o2, codegen, refcount, segfault]
blocked-by: []
summary: "A NINE-LINE NilPy program with no classes, no imports and no library calls SEGFAULTS at -O2, the shipped default level, identically on pin v418 (fda77c48b8ee) and at HEAD. THIS IS PURE x86-64 CODEGEN: frankh-c0 measured the IR BYTE-IDENTICAL at -O1, -O2 and -O3 (PXXDBG=a.ir:main, 72 lines, only the size banner differs), so no IR-level pass is involved, and disabling all seventeen `OptLevel >= 2` / `< 2` gates in ir_codegen.inc at once runs CLEAN -- the culprit is inside that set and c0 is bisecting it. TRIGGER, THREE CONDITIONS, all required and all measured: (1) a frame with EXACTLY THREE locals, (2) EXACTLY TWO of them tyPromoInt64 (tk=28) -- one runs clean and so do three -- and (3) a promo-int reaching `print` WITHOUT an explicit str(). `print(str(acc))` runs CLEAN on the identical frame where `print(acc)` segfaults, so the construct that selects the bad code is the IMPLICIT promo-int -> AnsiString conversion on the write path, NOT the frame layout and NOT the loop -- both of which this ticket blamed first. The third local's TYPE does not matter (Int64, AnsiString and Double all segfault) nor does its position. LEVEL MATRIX: -O0 clean, -O1 clean, -O2 SEGV, -O3 clean. READ -O3 AS MASKING, NOT AS ABSENCE: every gate is `OptLevel >= N`, so the ladder is monotonic and -O3 does everything -O2 does and more; a fix validated by "-O3 is clean" would be validating a mask. DCE IS EXONERATED IN BOTH DIRECTIONS: -O2 --no-dce still SEGVs and -O3 --no-dce is still clean. THE FAULT SITE IS AN UNCONFIRMED READING AND NO FIX MAY BE WRITTEN AGAINST IT: a refcount release sequence (`cmpq $0x40000000,-0x10(%rax)` then `decq -0x10(%rax)`) with rax=0x2aa6428c reads as a promo-int INLINE payload dereferenced as a heap bignum pointer -- but that is an interpretation of one register and four instructions, nobody has disassembled the emitted release site, and the suspect has already moved twice (off frame layout, then off the IR). Found while benchmarking perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program, whose coarse arm MASKS this crash by boxing the promo-int pair to tyVariant -- so narrowing that arm turns working programs into segfaults until this is fixed."
---

# Two promotable-int locals plus exactly one other local segfault at -O2

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

| level | rc |
| --- | --- |
| -O0 | 0 |
| -O1 | 0 |
| **-O2** | **139** |
| -O3 | 0 |
| default (no flag) | **139** |

`-O2` is the proven default, so every ordinary invocation hits it.

## Where it faults

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
> `-O1`, `-O2` and `-O3`, and an eliminated local would change the IR, so `-O3`
> does whatever it does BELOW the IR. The question "why is `-O3` clean" is also
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

### BISECT STATE, PAUSED NOT ABANDONED — `frankh-c0`, 2026-09-22

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
