---
slug: umbrella-track-p-and-a-have-no-open-bugs
title: "Track P and Track A carry no open bug tickets"
track: A
prio: 80
type: umbrella
blocked-by: []
created: 2026-09-07
owner: ""
summary: "GOAL, not a unit of work. Owner, 2026-09-07: 'i want bug report on track P and A to be empty.' Census AT CREATION, by folder rather than by a glob: 111 open bug tickets -- P 37 (backlog-pascal 32, working 5), A 74 (backlog-core 72, unfinished 1, working 1). The number is the deliverable and it is also the thing most easily faked, because a ticket moved to low-prio/ or rejected/ leaves the count exactly as a fixed one does. So this umbrella carries the census method and demands the SPLIT -- fixed vs correctly re-filed -- in every report against it. Two thematic clusters carry the bulk and are where the leverage is: managed types (27 across both tracks) and cross-target/backend (19, all A)."
---

# Track P and Track A carry no open bug tickets

**Owner, 2026-09-07:** *"i want bug report on track P and A to be empty."*

## The census at creation — 111 open bug tickets

Counted **by folder**, never by a glob across all of them, because a glob picks
up `done/` and that error has already cost this project a peer's census once.

```
TRACK P   37     backlog-pascal 32   working 5
TRACK A   74     backlog-core   72   unfinished 1   working 1
```

Prio bands, which is where the honesty problem lives:

```
P   60:3   50:10  40:15  30:6   20:2   10:1
A   70:1   60:6   50:4   40:19  30:26  20:15  10:1  0:2
```

**Method, so this is re-runnable and so a later reader can catch it going
stale:** open folders are everything except `done/ rejected/ known-incompat/
low-prio/ rainy-day/ float/`; a ticket is a bug if its slug starts with `bug-`.
Counting instead by the `type:` field gives **P 37 rather than 36** — one P
ticket is typed `bug` with a non-`bug-` slug. CLAUDE.md says bugs and features
are distinguished by the slug prefix, so the slug is the rule and the one-ticket
gap is a frontmatter inconsistency, not a disagreement about the world.

## The number is the deliverable AND the thing most easily faked

**A ticket moved to `low-prio/` leaves this count exactly as a fixed one does.**
That is not a hypothetical risk here: 18 of the 111 sit at prio 20 or below,
and the four terminal folders exist precisely so that a report which is wrong,
chosen, or not worth ranking can leave the queue honestly.

So **re-filing is legitimate and must be visible.** Every report against this
umbrella states the split:

- **fixed** — the defect is gone and something asserts it.
- **`rejected/`** — the report is WRONG: false premise, unreachable observable,
  or a construct only a mistaken program produces. *"On par with the language,
  not with FPC."*
- **`known-incompat/`** — the measurement is TRUE and reproducible and ours is
  the CHOSEN behaviour. Never "tolerated".
- **`low-prio/`** — real, probably correct, not worth ranker attention.

**A ticket that goes to a terminal folder needs the same evidence as a fix.**
Parking at prio 10 is explicitly not an option — CLAUDE.md: it keeps the ticket
in the ranker forever at zero value. And re-filing a ticket you have not
reproduced is how a real defect becomes invisible; the low bands are where this
umbrella will be tempted and where it should be slowest.

## The clusters — the leverage, not a taxonomy

Grouped by subject. **Two clusters carry more than half the total.**

```
managed types (string / array / interface / record)   P 9   A 18   = 27
cross-target / backend (i386 arm32 aarch64 riscv       P 0   A 19   = 19
                        xtensa wasm32, ABI)
generics / specialization                             P 7   A 2    =  9
overload / type resolution                            P 4   A 3    =  7
exceptions & control flow, const/sizeof/width,        P 2   A 7    =  9
release/finalize
unclustered                                           P 15  A 27   = 42
```

**Take a cluster, not a ticket.** CLAUDE.md: you cannot notice that eight
tickets share one cause while holding one of them, and the overhaul is often the
smaller job because it deletes cases. The managed-types and cross-target
clusters are the two most likely to collapse into far fewer changes than their
counts suggest — the scope-exit release loop already did exactly that, seven
copies becoming one classification.

**The unclustered 42 are not a residue to sweep last.** Anything that resists
grouping is either genuinely isolated — fine, and CLAUDE.md says so — or is
grouped on an axis this keyword pass could not see. Re-cluster it once the two
big ones are down rather than working it a ticket at a time.

## How to report progress against this

Re-run the census. **Give the delta AND the split** — "111 → 96: 11 fixed, 3
rejected, 1 known-incompat" is a report; "down to 96" is a number that cannot be
checked and hides the one thing worth watching.

## What this umbrella does NOT claim

Emptying these two backlogs is not the same as the compiler being correct: it is
the state of the **written record**, and the record only holds what someone
noticed and filed. Umbrellas grow by attempting a target, and the tickets that
arrive from an attempt are the ones that were actually blocking real use. **A
new bug filed against P or A while this runs is the umbrella working, not a
setback** — and closing this while refusing new reports would invert its whole
purpose.
