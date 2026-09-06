---
slug: decide-pair-the-pin-with-the-lib-rtl-it-is-coherent-with
track: U
type: decide
prio: 55
status: decided
owner: user
found: 2026-09-05
found-by: frankZ, filed by frank-coordinator
blocked-by: []
summary: "DECIDED 2026-09-06 BY THE OWNER: RTL coherence is a PRIMARY PURPOSE of pinning, pin on regular intervals EVEN WITH REDS, and PINS ARE NOT RELEASES. Landed in CLAUDE.md. The measurement behind it: USABLE ROLLBACK DEPTH IS ZERO. Measured across nine pins against the current tree's 54 `lib/rtl` root units: HEAD 0 failures, v404 2, v375..v403 all 14, v365 and v354 both 54. Every historical pin is STRICTLY WORSE than the current one, and `trackt pinstatus` names v354 as the recovery target -- so following the advice it prints moves you from 2 broken roots to 54. The cause is that `make revert` is `git checkout $SRC -- $(STABLE_DEFAULT_DIR)` and nothing else: the pin moves back and `lib/rtl` does not. NO ARGUMENT TO THAT COMMAND PRODUCES A COHERENT PAIR, because the pair is only coherent within one era -- each new builtin mints a cliff, roughly one a fortnight (`0f6a04644` __pxxblockmove 08-21, `31f8b11bf` System.TMethod 09-04). THIS IS NOT A REASON TO GATE A PIN and must never be read as one; if anything it argues for pinning MORE promptly, since the current pin is the best rollback target in existence. What it falsifies is a PREMISE, not a practice."
---

## 2026-09-06 (frank-coordinator, at frankuser's request) — TWO DATED CASUALTIES IN 48 HOURS, and the window is not diligence

This ticket has been arguing pin cadence from a rollback-depth measurement. Here are two dated
instances of the cost, in the other direction, so the decision carries casualties and not only a
premise. Both are the same shape and it now has a name: **"FIXED AT HEAD, INERT UNTIL PINNED."**

1. **`IEnumerator<T>.Current`, inert for a MONTH.** `property Current: T read GetCurrent;` was
   deliberately omitted from `lib/rtl/classes.pas` from 2026-08-30 because the pin of the day
   rejected a property in an interface. The parser fix that made it legal sat in `done/` — closed,
   correct, and doing nothing for its consumer — until pin **v404** (`8844c8c42`) carried it on
   09-05. Recorded on `feature-pascal-corpus-expansion`, attributed by ablation, and it was the
   last wall on corpus rung 6b.
2. **`pyvar_is_inttag` / `pyvar_is_objtag`, red right now.**
   [[bug-a-the-pinned-compiler-cannot-build-live-lib-rtl-and-nothing-tracks-it]]. frankZ's
   `8374118ec` (09-05 23:15) exports two builtins that two `lib/rtl` units call. Pin v404 is
   `8844c8c42` (09-05 20:17) — **three hours earlier**, and
   `git merge-base --is-ancestor 8374118ec 8844c8c42` is **false**. Track T's full tier at
   `b77ac29` is RED on `lib-test` for exactly those two identifiers.

**THE STRUCTURAL POINT, WHICH IS FRANKUSER'S AND IS WHY THIS IS A DECISION RATHER THAN A
CHECKLIST ITEM.** A `lib/**`-facing compiler fix is only real once pinned; pinning is owner-only;
the owner sleeps. **So the window between "fixed" and "real" is not a few minutes of diligence —
it is however long until a human is awake**, and every ticket closed inside that window is
*honestly closed and observably wrong to everyone downstream*. Adding "check whether a pin carries
it, and say so in the resolution" to the closing discipline is right and should be kept: it makes
the gap VISIBLE. **It cannot make the gap SHORTER.** Only a cadence answer does that, which is
what this ticket is for.

Note the two casualties point the same way as this ticket's own measurement: v404 is the best
rollback target in existence and every historical pin is strictly worse, so both the rollback
argument and the inert-fix argument say **pin more promptly**, not less. Neither is a reason to
GATE a pin, and neither may be read as one.

Not ranked or re-prioritised by this seat — `owner: user`, and `make pin` is owner-only.

# Pair the pin with the `lib/rtl` it is coherent with

## The measurement

frankZ, nine pins, each asked to compile the current tree's **54 `lib/rtl` root
units**:

| pin | root units it cannot compile |
| --- | --- |
| HEAD | **0** |
| v404 (current) | **2** |
| v375 … v403 | **14** each |
| v365 | **54** |
| v354 | **54** |

> **Usable rollback depth is ZERO.** Every historical pin is strictly worse than
> the one in place.

And `trackt pinstatus` names **v354** as the recovery target, selected by
`pin_is_green()`. **Following the advice it prints takes you from 2 broken roots
to 54.**

## The fork

`make revert` is `git checkout $SRC -- $(STABLE_DEFAULT_DIR)` and nothing else,
so **the pin moves back and `lib/rtl` does not.** Incoherent by construction.

**And no argument to that command fixes it, because the pair is only coherent
within one era.** Each new builtin mints a cliff: `0f6a04644` minting
`__pxxblockmove` on 08-21, `31f8b11bf` minting `System.TMethod` on 09-04 —
**roughly one builtin a fortnight and one cliff per builtin.**

Options, none of them small, which is why this is a `decide-` and not a fix:

1. **Revert the pair.** `make revert` moves `stable_linux_amd64/**` *and* the
   `lib/rtl` tree to the same era. Restores real rollback; means a revert is no
   longer a one-directory operation and interacts with whatever else has landed
   in `lib/rtl` since.
2. **Pin the pair.** `make pin` records the `lib/rtl` era alongside the binary, so
   a pin is a self-contained artefact. More storage, and the coherent unit becomes
   the thing to reason about rather than the binary.
3. **Accept depth zero and say so.** Rollback stops being a recovery story; the
   remedy for a bad pin becomes *pin again from a fixed tree*. Cheapest, and it
   requires deleting the recovery clause everywhere it is cited rather than
   leaving it hollow.

**Recommendation: 3 now and 1 or 2 deliberately.** Option 3 costs nothing, is
already true in fact, and stops the false clause being quoted; the design change
can then be ranked on its own merits instead of under time pressure from a red.

## What this is NOT

**It is not a reason to gate, delay or condition a pin.** frankZ put that in its
own ticket in those words and it must survive relay:

> **A valid pin is the self-host fixedpoint. Nothing else may block one.**

If anything this argues for pinning **more** promptly — **the current pin is the
best rollback target in existence, and every hour it ages the gap widens.**

**What it falsifies is a premise, not a practice.** *"A red is a reason to pin
sooner, not later"* is sound **only while recovery works**, and `track-t.md`'s
*"a bad pin is recovered, not prevented"* has not been true for some time.
**Either that claim becomes true again or it stops being cited.** What it must not
do is keep being quoted as load-bearing while it is hollow — which is exactly
what it was being quoted for on the night this was measured, by this coordinator,
to four sessions.

## Split out deliberately

**`bug-t-pinstatus-names-a-rollback-target-nobody-validated`** is the cheap half
and is **not** part of this decision, so it can land without waiting on the design
call: `pinstatus` has the canary's logic to hand and should either run it or mark
the line unvalidated. **A tool naming a target nobody validated is worse than a
tool naming none.**

## 2026-09-06 — DECIDED BY THE OWNER

Owner, verbatim, asked directly with this ticket in front of him:

> *"yes staying in sync with the rtl is a primary purpose of pinning. this is
> also why we have to pin on regular intervals, even if there are reds. pins are
> not releases."*

**Three things settled, and the third is the one that explains the other two.**

1. **RTL coherence is a PURPOSE of pinning, not a side effect.** The pin and
   `lib/rtl` are one artefact. This ticket's measurement — usable rollback depth
   zero, every historical pin strictly worse than the current one — is not a
   defect to be repaired by making `make revert` smarter. It is what pairing
   looks like from the other end: the pair is only coherent within one era, so
   the way to have a coherent pair is to MINT ONE OFTEN.

2. **Pin on regular intervals, EVEN IF THERE ARE REDS.** This ratifies the
   existing graded-not-gated rule rather than adding to it, and it closes the
   reading that keeps coming back — that a red is a reason to wait. It is not.
   The pin in place is red too, and a policy of refusing on reds is an argument
   for never leaving a red pin, which is how v354 stayed the last green one for
   19 days.

3. **PINS ARE NOT RELEASES.** This is the frame the whole argument was missing.
   Every instinct that says "do not pin while something is red" is release
   instinct — the fear of shipping a defect to someone who cannot roll back. A
   pin ships to the fleet's own inner loop, is replaced within hours, and its
   only irreplaceable property is that the compiler reproduces itself. Applying
   release standards to it produces exactly the outcome release standards exist
   to prevent: in the 49-hour gap, no pin at all, which the owner had already
   called *"a worse outcome"* on 2026-09-01.

**What this does NOT authorise:** running `make pin`. That is still the owner's
alone and a relayed authorisation is not verifiable by the seat receiving it —
see the 2026-09-06 refusal, which was correct. This ticket settles the POLICY;
the act still needs him.
