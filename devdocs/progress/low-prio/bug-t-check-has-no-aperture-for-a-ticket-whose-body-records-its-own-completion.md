---
track: T
prio: 60
type: bug
status: low-prio
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

## A second live instance, 2026-09-02 — and this ticket was duplicated

frankZ hit the same defect in the wild: conformance shard0 was claude-T's fix
from 09-01, still wired as an umbrella blocker three days later, because the
BODY said RESOLVED and the frontmatter did not. `ready`/`next` kept handing it
out. Same mechanism as the 2026-08-30 `feature-random-library` dispatch above,
so this is a recurrence and not a one-off.

A loose scan finds **~15 candidates** across the open folders. **That number is
not trustworthy** and must not be used as a work estimate: it comes from
grepping bodies for resolution-shaped prose, which is a filter answering about
the filter list rather than about the repo. It is a reason to build the aperture,
not a backlog.

**This ticket was filed a second time**, as
`bug-t-tickets-announce-resolution-in-the-body-while-frontmatter-keeps-them-open`
(frankuser, 2026-09-02, prio 60), by a session that searched and did not find
this one. Merged here and the duplicate deleted. The duplication is itself
evidence for the aperture: the 74-ticket Track T backlog is not searchable
enough for a filer to reliably discover that their finding already exists, and
`check` has no aperture for a duplicate either.

**Prio raised 45 -> 60**, taking the duplicate's number: two independent live
dispatch costs in four days is a higher rate than the original filing knew about.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
