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
