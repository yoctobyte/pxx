---
track: T
prio: 45
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "`progress.sh check` finds prose blockers whose ticket has CLOSED (STALE-PARK) and prose edges never wired into frontmatter (PROSE-EDGE-NOT-IN-FRONTMATTER). It has no aperture for the mirror case: a ticket whose own BODY records the work as finished while its frontmatter and status line still advertise it as open. Cost a dispatch on 2026-08-30 -- feature-random-library was dispatched on a status line reading 'HW tiers and thread-safe state' when its own log recorded the thread-safe half landing 2026-07-20 and a 2026-08-28 pass concluding 'Nothing here is Track B work. Tier 1 is closed.'"
---

# `check` cannot see a ticket that already says it is done

- **Type:** bug (Track T — the board tooling). Proposed by frankB 2026-08-30
  after closing `feature-random-library` on verification with **no source
  changed**.

## The gap, stated against the apertures that already exist

`check` has two prose-vs-frontmatter apertures and they cover opposite halves of
one idea:

| aperture | finds |
| --- | --- |
| `STALE-PARK` / `STALE-PARK-HELD` | prose names a blocker that has since **closed** — the resume condition may be met |
| `PROSE-EDGE-NOT-IN-FRONTMATTER` | prose states a block the `blocked-by` field never carried — nothing propagates |
| **(missing)** | **the body records the work as DONE while the frontmatter says open** |

The first two ask whether a ticket's *dependencies* moved. The missing one asks
whether the *ticket itself* did. Nothing re-reads a ticket's own log against its
own status line, so a summary written once outlives every entry beneath it.

## What it cost

`feature-random-library` [B p45] was dispatched to frankB on a status line
reading *"remaining work is HW tiers and thread-safe state"*. Inside the same
file:

- the log records **thread-safe state landing 2026-07-20**;
- a frankB pass on **2026-08-28** concluded *"Nothing here is Track B work. Tier 1
  is closed."*

Two of three "Remaining" entries were already stale when that pass was written;
by 2026-08-30 all three were. **None of it was wrong when written.** frankB
verified by running rather than trusting either record — software tier against
its oracle, `lib_randomstate` printing `RANDOMSTATE OK`, tier 1 confirmed live
with `HWEntropyAvailable` TRUE and three distinct `HWEntropy64` draws on a box
whose cpuinfo carries `rdrand`, and four oracle targets building — then resolved
it with no source changed.

**The tier-1 row is why a build check would not have done**: the not-available
branch returns cleanly and is indistinguishable from outside, so on a machine
where the intrinsic never fires, a compile-only check passes while proving
nothing.

## Suggested aperture

Flag a ticket in a **ranked** folder whose body contains a completion phrase
(*"is closed"*, *"landed YYYY-MM-DD"*, *"nothing here is ... work"*, *"already
done"*) dated **after** the newest entry its Status/Remaining section reflects.
Report it, never auto-close: **a body saying "tier 1 is closed" and a ticket being
closable are different claims**, and only the second needs a human or a measured
verification run.

Sibling apertures worth the same treatment are listed in
[[bug-t-check-has-no-aperture-for-a-stale-grant-or-an-absent-holder]] — same
family: the board records a state, nothing re-reads it, and the two switches that
would cover for each other go stale together.

## frankB's own statement of it

> **A ticket's "Remaining" section is a claim with a date on it, exactly like its
> status line.**
