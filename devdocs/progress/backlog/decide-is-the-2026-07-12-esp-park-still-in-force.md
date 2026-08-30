---
slug: decide-is-the-2026-07-12-esp-park-still-in-force
track: U
prio: 65
type: decide
status: open
found: 2026-08-30
---

# DECIDE: is the 2026-07-12 ESP park still in force? 23 ranked tickets and a staffed agent depend on it

Raised by frankB, which found the park while working an ESP ticket **I dispatched it to**,
and said so on the record rather than burying it: *"that is a user priority call and not
something a thin queue should quietly erode."* It is right, and I cannot settle it.

## The two facts that disagree

**The park.** *"ESP parked (user 2026-07-12): Pascal has prio."* Recorded as a **comment on a
`prio:` field in one `done/` ticket**, and restated in the prose of one backlog ticket. That
is its entire existence.

**The campaign.** CLAUDE.md's Track S section describes ESP as a live lane with a stated
primary target, and cites a **later** owner ruling — xtensa is primary, riscv32 is what works
today. `~/frank.sh` gained a dedicated `frankS` on **2026-08-29**, added by the coordinator
because *"the ESP32/SoC campaign had 12 ranked tickets and no agent."*

## Why I am escalating instead of deciding

A July park and an August campaign description are not obviously reconcilable, and the
tie-breaker is your intent, not anything in the tree. Both readings are defensible:

1. **The park was superseded** by the later xtensa ruling and by S being surfaced as a formal
   lane. Then everything done tonight is correct and the stale comment should be struck.
2. **The park still stands** and Pascal still has priority. Then the fleet spent a night on a
   parked campaign, 23 ranked rows should be re-priced down, and frankS should be stood down
   or re-lane.

I am not guessing between them. Guessing costs a night of work in one direction or an
incorrectly-parked campaign in the other.

## What this cost while unresolved, stated plainly

I staffed frankS onto ESP, dispatched frankB to `feature-dns-esp-backend`, and **filed two
new ESP tickets myself tonight at p70 and p65**. If the park stands, all of that was me
eroding a user priority call, and none of it was deliberate — because **the park has no
mechanism.** 23 ESP/xtensa rows are ranked and dispatchable right now.

## The general defect, which is fixable regardless of the answer

This is the **second** instance today of a user decision enforced only by a number:
`bug-nilpy-except-tuple-binder` was held on 2026-08-14 and priced to 20, and a bulk re-triage
on 2026-08-25 swept it to 55 — it has ranked ever since. Repaired by giving it the `NOT
DISPATCHABLE` marker, which survives re-pricing because it is not a price.

**A park recorded as a prio comment is not a park.** Whichever way this ruling goes, if you
park a *campaign* again the durable form is the marker (or an explicit `gated-by:` on a
`decide-`), not a number and not a comment — because a comment on one ticket cannot reach the
other 22, and the ranker never reads it.

## What I need

One word. *Superseded* → I strike the stale comment, keep the lane, and note the
supersession. *Still parked* → I re-price the S rows, stand frankS down, and record it where
the ranker can see it this time.


## Chronology, added 2026-08-30 — and it sharpens the fork rather than settling it

frankB supplied the ordering; I checked the middle term against a source it did not choose,
and found a fourth data point it had not claimed.

| when | what |
| --- | --- |
| **2026-07-12** | the park: *"ESP parked (user 2026-07-12): Pascal has prio"* |
| **2026-08-02** | ESP work actively progressing — see below |
| later | CLAUDE.md's Track S written as a live lane, *"Primary target is xtensa (the user's S2/S3 hardware); riscv32 (C3) is what works today"* (undated) |
| **2026-08-29** | the coordinator adds a dedicated `frankS` to `~/frank.sh` |

**frankB's point, and it is the sharpest statement of the ambiguity:**

> a target-priority ruling is not the same as a work-priority ruling, and *"when we do ESP,
> do xtensa first"* is entirely consistent with *"don't do ESP yet"*.

So the later xtensa ruling does **not** by itself supersede the park. It answers a different
question. That is the strongest argument that this genuinely needs you rather than a
coordinator reading.

**Precision on the middle row, because the distinction matters.** frankB cites a *2026-08-02
user correction that xtensa is the primary ESP target*, recorded in its own ticket — I am
relaying that on its citation and have **not** independently found the ruling text. What I
did find, in files neither of us picked for this purpose, is that **ESP work was actively
progressing on 2026-08-02**: `feature-esp-hardware-flash-validation.md` — *"Everything except
the board is now in place (2026-08-02)"* and *"The peripheral half is unblocked too
(2026-08-02, later)"*; `feature-a-promoint-variant-esp-targets.md` carries a dated
2026-08-02 diagnosis.

**Which is a fourth fact and possibly the most useful one: the park was already not being
observed three weeks after it was made, by sessions that had nothing to do with tonight.**
Tonight's staffing is the largest instance, not the first. That is consistent with either
reading — the park was understood as superseded, or it has been invisible to every session
since the day it was written — and those two are indistinguishable from the tree, which is
exactly why this is a U ticket.

## What this does not change

Still one word. But if the answer is *still parked*, the follow-on is bigger than re-pricing
23 rows: work has been landing against a parked campaign for seven weeks, and some of it is
in `done/`.
