---
track: T
prio: 60
type: bug
blocked-by: []
found: 2026-09-02
found-by: frankb-a9
owner: —
summary: "tools/exit_observable_devtest.py's stdout-only SHARE ratchet is armed at 647/698 = 92.6934%, but the tree of its OWN arming commit (67cf9588a) measures 650/701 = 92.72% — so it has been RED since the moment it landed, by three rows, before anyone added anything. A further +17 arrived at b098c63c6, taking it to 667/718 = 92.9068%. Every full tier since has carried tools-devtest#00 FAIL for this row. Not diagnosed further and deliberately NOT re-armed: the owner capped rather than ratified twice today, and choosing cap-vs-re-arm is that judgement, not a mechanical fix."
status: done
---

# The exit-observable share ratchet was red before anything drifted

## What is measured

`tools/exit_observable_devtest.py` reads the Makefile and counts cross-target
differential rows (`run_target.sh`, two or more `"$$(` captures). The ratchet
is the SHARE of those that compare **stdout alone** — i.e. leave the exit code
free and unclaimed. It is deliberately armed AT the measured value so that one
new uncapped row trips it, with a paired assert proving that bound is tight.

That design is right and this ticket does not argue with it.

## The arithmetic

Running the guard unchanged against successive Makefiles, restoring after each:

| tree | measured | verdict |
| --- | --- | --- |
| `67cf9588a^` (before the arm) | 655 of 701 = 93.44% | — |
| **`67cf9588a` (the arming commit)** | **650 of 701 = 92.72%** | **RED against its own 92.6934%** |
| `b098c63c6` | 667 of 718 = 92.90% | RED |
| `277e082b5` | 667 of 718 = 92.90% | RED |
| `dcb6f2c17` | 667 of 718 = 92.90% | RED |

The commit that armed it capped five arm32 leak rows (655 → 650 uncapped) and
recorded **647 of 698**. Its own tree measures **650 of 701**. Three rows, in
both numerator and denominator — so the figure was taken from a tree that then
moved before the commit closed, and nothing re-derived it.

Then `b098c63c6` added 17 more uncapped rows, which is the ratchet working as
designed. But it had nothing left to detect: it was already failing.

## Why this is the shape it is

The armed constant is a NUMBER IN PROSE that nothing re-derives — the same
defect this very file fixed one row above, where a label said "still ~536"
while measuring 561. The fix there was to print the live count beside the
quoted one. The armed value did not get the same treatment, so it can be three
rows stale and look exactly like a real breach.

**A gate that cannot pass is not a gate.** Since it landed, `tools-devtest#00`
has been FAIL in every full tier, which means the row carries no information:
a real drift arriving tomorrow is indistinguishable from the state it has been
in since birth.

## Why this is filed rather than fixed

Two different repairs, and the choice is a policy call the owner has made
deliberately twice today — the arming commit's own message says the ratchet
tripped and it was **not** re-armed upward, and that five rows were CAPPED
instead of ratifying the drift.

1. **Cap the 17** rows `b098c63c6` added, which is the documented intent
   ("adding rows correctly cannot trip it"). Needs knowing which rows and
   whether their expectations can carry `exit=0`.
2. **Re-arm at the arming tree's real measurement** (650/701 = 92.72%), which
   fixes only the three-row birth defect and leaves the 17 as a genuine breach.

They are not alternatives — (2) is needed regardless, or the next arming is
stale the same way. Whoever takes it should also consider making the guard
DERIVE and print the armed figure's provenance the way the population floor
already does, so a stale constant announces itself.

## Provenance

Found because a full tier run at `dcb6f2c17` came back with exactly one FAIL.
Checked first whether it was mine: removing the four Makefile rows that commit
added leaves the count identical at 667/718, because those are x86-64
`$(COMPILER)` rows and the population is `run_target.sh` cross-target rows.
It is not mine, and it is not `b098c63c6`'s alone either.

## Resolved 2026-09-04 by frankZ — with a third repair, not either of the two

Neither option. The ratchet is **retired** and replaced with the half a
growing corpus cannot move: the rows that DO capture the exit code may not be
given back, floored at the measured 53.

**Why not (1) cap the rows.** Capping is not free, and this ticket could not
see that from the arithmetic. `chore-t-make-every-cross-target-row-assert-the-
exit-code` (T, p45, low-prio) records the reason: `run_target.sh` returns the
EMULATOR's status, and signal deaths do not encode identically under qemu-user
and a native shell, so a blanket rollout manufactures diffs on exactly the rows
most worth checking. It wants a piloted rollout, one arch at a time. So the
devtest was reddening the tier every few hours to demand work the ranker had
deliberately deferred and flagged as hazardous.

**Why not (2) re-arm at the arming tree's real figure.** It fixes the birth
defect and leaves the design intact — and the design is what cannot survive.
The bound is armed with a positive control asserting that ONE more uncapped row
breaches it. That is zero marginal headroom, and the corpus gains **~20
uncapped rows an hour** from five lanes: measured off
`git show <sha>:Makefile | grep -c run_target.sh` at six points on 2026-09-04,
1068 -> 1197 call sites between 06:11 and 17:48. Any correct re-arming is red
again within the hour. The three-row staleness this ticket found is real and is
not the reason it fails.

**Two independent readings, and they fail differently**, which is why this is
not one argument twice. frankb-a9 ran the guard against successive historical
trees and found it red at birth. I measured the marginal headroom against the
corpus growth rate at HEAD. Neither could produce the other's number, and both
land on this ticket's own sentence: *a gate that cannot pass is not a gate*.

**What replaces it.** `len(capped) >= 53`, with its own positive control that
strips the capture off a real row and asserts the floor stops recognising it
(53 -> 52, checked on every run). Growth leaves it untouched; a capture deleted
or rewritten away — the one shape that is a genuine regression — still fails
it. The 905-of-958 exposure is PRINTED on every run and pointed at its two live
tickets, so it stays visible where a reader will see it and ranked where
ranking belongs.

The provenance advice is taken in spirit: there is no longer an armed constant
in prose to go stale, and the one remaining number prints its own measurement
date and the value it replaced.

Landed `3914444ff`. `make tools-devtest` 134 guards green, was 131 green /
3 RED.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit f5200b8a4.
