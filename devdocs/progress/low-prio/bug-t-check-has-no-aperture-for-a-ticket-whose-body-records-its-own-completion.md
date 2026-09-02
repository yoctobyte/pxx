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


## Third live instance, 2026-09-02 — found while dispatching, not while auditing

`bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string` sat at
`status: backlog`, **prio 70, second in `ready --track P`**, while its fix had
been on origin since 02:03 that morning (`9c6b216aa`, 14 assertions added). Its
own summary ended *"Fixed by teaching the oracle AN_FIELD and AN_DEREF"* — past
tense, in the one field everybody reads — and a SECOND ticket
(`regression-lib-test-lib-synapse-3`) named it as the thing that fixed them.

**Two independent documents said it was done and the ranker kept offering it.**

Cost this time: it was about to be handed to an agent as work. The previous two
instances cost a dispatch each; this one was caught only because the coordinator
happened to read the queue before relaying it, which is not a mechanism.

Note the aperture would not even need prose analysis here — a ticket whose
summary contains "Fixed by" while its status is `backlog` is a one-line grep.
That is not the general case, but it is a cheap first cut that would have caught
all three.

## 2026-09-02 (frankA) — the proposed one-line grep, tested against the three cases that motivated it

The section above offers a cheap first cut: *"a ticket whose summary contains
'Fixed by' while its status is `backlog` is a one-line grep... it would have
caught all three."* It was worth running before building anything on it.

**It catches one of the three.**

| instance | summary text | `Fixed by` | sentence-initial `Fixed`/`FIXED` | `fixed at\|by\|in` |
| --- | --- | --- | --- | --- |
| `feature-random-library` | **there is no `summary:` field at all** | — | — | — |
| `bug-p-a-char-array-…-is-not-a-string` | `…Fixed by teaching the oracle…` | yes | yes | yes |
| `regression-test-c-conformance-shard2-6-2` | `FIXED at 0ee41312d.` | **no** | yes | yes |

The first instance is uncatchable by ANY summary filter — its ticket has no
summary field, which is worth knowing on its own, because the aperture as
described reads a field that is not universally present. The third says
`FIXED at`, not `Fixed by`, and is the most recent one.

### And on the open board, precision matters more than the wording suggests

Run over every open folder (`backlog`, `backlog-*`, `urgent`, `low-prio`),
excluding `README.md`:

| filter | open hits | true |
| --- | --- | --- |
| `fixed at\|by\|in`, `is fixed`, `already fixed` | 17 | 3 |
| `Fixed by` (the proposal) | 7 | 3 |
| sentence-initial `Fixed`/`FIXED` | 2 | 1 |
| **summary's FIRST WORD is `FIXED`/`Fixed`** | **1** | **1** |

**The false positives are not noise, they are the house style.** Every one of
the five `backlog-core` hits reads *"<some OTHER ticket> was fixed by X, and the
residual is Y"* — which is exactly how this repo banks a residual so an
exculpation has an owner, and it is indistinguishable from "this ticket is done"
by any filter that only looks for the WORD. The aperture needs the sentence's
SUBJECT.

`feature-embed-pascal-script` is the sharpest example: its summary is
*"ATTEMPTED… (1) …FIXED, (2) …FIXED, (3) STILL OPEN"*. Two of its three walls
are down and the ticket is correctly open.

### What the run actually found

Four tickets closed on it, all verified rather than closed on the grep:

- `regression-lib-test-lib-synapse-3`, `-ssl`, `-transitive-unit` — all four
  synapse programs rebuilt at pin v400 and matched against the Makefile's own
  expected text.
- `bug-a-set-membership-truncates-the-test-value-on-32-bit-backends` — summary's
  first word is `FIXED`, sat at prio 25 in `backlog-core`. Its test runs clean
  at HEAD and is wired at eight Makefile sites.

That last one is the case for the aperture that the three recorded instances do
not make. All three of those were caught because somebody was about to be handed
the work; **this one was at prio 25 and nobody was ever going to be**. A ticket
too low to dispatch is exactly the one no human will notice is already done.

### Two more duplicates found while doing it

`regression-lib-test-lib-synapse-ssl` and `-transitive-unit` each existed in
BOTH `backlog/` and `done/`, byte-identical apart from the auto-close Log entry
— [[bug-t-the-watcher-auto-close-copies-a-ticket-into-done-instead-of-moving-it]]
reproducing exactly as it predicted, on 2026-09-02, while the ranker kept
offering the `backlog/` copies. Removed. `tools/ticket_path.sh --check-dupes`
now reports the board clean; it is what surfaced both.

### Track T's reading of the same numbers, which reverses what they argue for

Relayed by the Track T session after the run above, and it is right:

> "the filter only catches 1 of 3" reads as a reason not to build it and your
> data says the opposite for the population that actually matters.

The precision table was measured against the three RECORDED instances, and all
three were found because a dispatch was about to happen — a population where a
false positive costs an agent's turn and precision therefore matters. The
`prio: 25` find is from a different population: nobody was going to be handed
that ticket, so nothing else was ever going to catch it, and the only cost of a
false positive there is one glance at a summary that a human is not reading
anyway.

**So the aperture's value does not depend on its precision, and the 17-hits /
3-true row is not the argument against it that it looks like.** 14 false
positives on a board scan are 14 glances; the alternative is a ticket sitting in
the ranker at zero value forever, which is the exact failure CLAUDE.md invokes
to argue for a terminal folder over a low prio. Report-never-auto-close (already
this ticket's design) is what makes a loose filter safe: the filter decides who
gets LOOKED at, and the verification decides who gets closed.

Which does NOT rehabilitate the wording-only filter for the dispatch population
— the "subject of the sentence" finding above stands, and `feature-embed-pascal-script`
is still a correctly-open ticket saying FIXED twice. It means the two
populations want different thresholds, and only one of them wants a tight one.
