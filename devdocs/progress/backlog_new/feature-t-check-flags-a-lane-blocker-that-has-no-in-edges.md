---
track: T
prio: 40
type: feature
blocked-by: []
status: backlog
summary: "prio propagates down dependency edges, so a ticket with in-degree zero inherits nothing — and a ticket that blocks a LANE rather than a ticket never gets an edge, because blocked-by: would be a false claim. Such a ticket under-ranks itself permanently and no checker sees it: from the ranker's side an in-degree of zero is indistinguishable from a leaf. Proposal: `progress.sh check` flags a ticket whose body names a track as its beneficiary and has no in-edges. Threshold MUST be calibrated against the live board before landing."
---

# `check` should flag a lane-blocker that has no in-edges

- **Track T** (`tools/progress.sh`, the board checks) — filed 2026-08-29 by
  frankC at frank-coordinator's request, out of a live instance the same day.

## The gap

The board's ranking model is *"one human `prio:` propagated down dependency
edges — a blocker inherits the priority of what it unblocks, so you rate goals
and the chain follows."* That is a good model and it has one blind spot:

**Propagation is only as good as the edges someone drew, and a structural
blocker is exactly the kind that never gets one — because it blocks a LANE, not
a ticket.**

From the ranker's side, **an in-degree of zero is indistinguishable from a
leaf.** A ticket nothing points at is either genuinely terminal work or a
mis-ranked keystone, and nothing in the tooling can tell the two apart.

## The instance that produced this

[[refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed]]
sat at `prio: 45` while ranked **below five tickets it is the blocker for**:

```
$ grep -rl "c-exclusive-lowering" devdocs/progress/{urgent,backlog,backlog_new,unfinished,blocked}/
$          # zero files
```

No in-edges, so it inherited nothing, so it stayed put. It was raised to 60 **by
hand** by the coordinator.

**The edges were not merely forgotten, and adding them would have been a false
claim.** `blocked-by:` means *cannot proceed*, and those five Track C tickets can
proceed perfectly well — by an agent holding the Track A slot. Marking them
blocked would hide real Track A work inside Track C's queue in order to repair a
ranking artefact: a second path encoding the truth somewhere nobody reads. The
honest lever was `prio:`, which is a human edit no checker prompted.

**That is what makes this a `check` problem and not a data-entry problem.** The
board was correct; the ranker could not see what the board meant.

## Proposal

Flag, do not rank. `check` reports; a human moves `prio:`.

A candidate is a ticket that **has no in-edges** (nothing names it in
`blocked-by:`) **and whose body claims a lane-wide beneficiary**. Signals worth
testing, cheapest first:

* a track letter named in the body's own prose that differs from the
  frontmatter's (this ticket is `track: A`, its beneficiary is C);
* phrases of the shape "Track X cannot be staffed", "most of Track X", "every
  ticket in X", "unblocks N tickets";
* a slug containing `-cannot-`, `-has-no-`, `-blocks-`;
* several tickets in one track whose bodies cite this one's slug **outside**
  `blocked-by:` — the prose-citation edge, which `check` already warns it cannot
  see (*"a blocking claim made in a ticket's PROSE is not checked and cannot
  be"*). That note and this ticket are the same gap from two sides, and the
  prose-citation count is probably the strongest single signal here.

## Calibrate before landing — this is the load-bearing condition

**Measure the rule against the live board and record the rejected thresholds**,
the way the last check to ship here was measured over 341 tickets with its
alternative written down. The failure mode is specific: a check that fires on
ordinary leaves teaches everyone to scroll past `check` output, and that costs
more than this ticket saves — `check` already emits `DEAD-COMMIT: 350
citation(s)`, which is exactly the line people have learned to skip.

Target something like **single-digit hits across the whole board**. If the rule
cannot get there, report that as the finding and do not land it; "we measured it
and the signal is not separable" is a real answer and belongs in this ticket.

## Not in scope

Auto-adjusting `prio:`. The coordinator's call on the instance above was that
the human lever is the honest one, and a checker that silently re-ranked would
reintroduce the same problem one level up — an invisible mechanism deciding
priority. **Flag it; let a person move the number.**

## Gate

Track T's own, for a Track T tooling change — plus the calibration run and its
numbers recorded in this ticket before it resolves. Note per CLAUDE.md that a
`Gate:` line naming a long local suite is superseded by the per-fix loop
(`decide-gate-line-convention`); the calibration numbers are the real deliverable
here, not a suite run.
