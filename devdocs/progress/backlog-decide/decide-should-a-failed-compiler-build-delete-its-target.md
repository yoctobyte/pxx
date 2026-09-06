---
slug: decide-should-a-failed-compiler-build-delete-its-target
track: U
type: decide
prio: 40
status: backlog
created: 2026-09-06
found-by: frankS
owner: ""
blocked-by: []
summary: "A failed `make compiler/pascal26` leaves the PREVIOUS binary on disk -- the Makefile has no `.DELETE_ON_ERROR` -- so the probe you run next executes the code your change was replacing and prints a plausible correct answer. Measured 2026-09-06: frankS nearly certified a positive control on output produced by the previous build. It is a fifth route to a stale binary beside CLAUDE.md's four, and the only one CAUSED BY THE THING BEING TESTED, so the failures are perfectly correlated -- the worse the change, the more certain you are to measure the old compiler. THE FORK: add `.DELETE_ON_ERROR` (a failed build leaves NO binary, so the wrong measurement becomes impossible rather than merely discouraged) versus leave it and rely on a one-line rule. THE COST IS THE REASON THIS IS A DECISION AND NOT A FIX: every failed edit would then cost a pin-seeded rebuild instead of a 12-second one, and a failed edit is the COMMON case in this loop, not the rare one. Fleet-wide trade, nobody's lane to take alone. Recommendation: the rule, not the Makefile change -- held WEAKLY, because the two rates are not commensurable: A's cost is certain and measurable while A's benefit is measured by SELF-REPORT, which is blind precisely to the cases where the hazard did its damage (a seat that does not catch it files a CONCLUSION, not a correction). Two instances in one day is a floor over the visibly-failed subset, not a rate."
---

# Should a failed compiler build delete its target?

- **Track U.** Files if it goes ahead: `Makefile` (one line). The alternative
  costs nothing in the tree and one line of prose in `CLAUDE.md`, which is the
  owner's file.
- Found by frankS while landing `af9c92a6f`, from inside the failure: the
  positive control for a new guard passed, on output produced by the previous
  build, because the compile had errored and the binary was never rewritten.

## The mechanism

GNU make deletes a target on recipe failure only under `.DELETE_ON_ERROR`. This
Makefile has none, so a failed `$(COMPILER_STAMP)` recipe leaves
`compiler/pascal26` exactly as it was. **Nothing is corrupt — that would be
loud.** What survives is a *working binary built from the previous source*: it
runs, it exits 0, and it answers about code you have just changed.

`compiler/pascal26` is untracked, so `git status` says nothing about it, and the
`converged` / `verified` verbs — the tell CLAUDE.md already documents — are
simply absent rather than wrong when the compile failed.

## Why it is worse than the four routes already documented

`CLAUDE.md` lists a seeded tree, a reverted experiment, a sync that pulled
someone's `compiler/**`, and the positive-control revert cycle. **All four are
accidents of housekeeping and are uncorrelated with your change.** This one fires
*precisely when your change does not compile*, which is exactly the moment you
are about to look at output — so the two failures are perfectly correlated: **the
worse your change, the more certain you are to measure the old compiler.** A
change that compiles cannot hit it.

## The fork

**A — add `.DELETE_ON_ERROR`.** The wrong measurement becomes *impossible*: a
failed build leaves no binary and the probe cannot run at all. This is the
strongest form of the guard, and it converts a silent failure into a loud one,
which is what this repo's whole instrument doctrine asks for.

**B — leave it, and carry a one-line rule.** *Neither `converged after N
round(s)` nor `self-host fixedpoint: verified` prints when the compile failed, so
the check is: did I see either verb since my last edit* — plus `make … && ./probe`
rather than two statements separated by `;`, which is exactly the shape that runs
the old binary.

**The cost is what makes this a decision.** Under A, **every failed edit costs a
pin-seeded rebuild rather than a 12-second one**, and in this loop a failed edit
is the *common* case, not the rare one. That is a tax the whole fleet pays on its
most frequent action, to close a hazard that a one-line habit also closes.
frankS's own position, and the reason they filed rather than did it: *"that is a
trade the whole fleet pays and I do not think it is mine to make."*

## THE TWO RATES BEING COMPARED ARE NOT COMMENSURABLE — read this before the recommendation

Added 2026-09-06 after frankuser corrected the first version of this ticket, and
it is the paragraph most likely to decide the fork, so it goes above the
recommendation rather than below it.

The cost of A is **measurable and certain**: every failed edit pays a pin-seeded
rebuild, and a failed edit is the common case.

The benefit of A is measured by **self-report, and self-report is blind precisely
to the cases where the hazard did its damage.** Both known instances share one
property: the seat **caught it themselves and then said so**. That is the only
path by which an instance becomes countable. **A seat that does not catch it does
not file a correction — it files a CONCLUSION**, and the conclusion is specific,
plausible and wrong. frankB's is the illustration: the old terminus warning fired,
*"which is precisely what a non-firing arm would look like"*. Undetected instances
leave a ticket, a resolution or a closed row, not a confession.

**So "twice in one day" is not a rate. It is a floor over the subset that failed
visibly enough to notice.**

> **Options weighed on observed frequency will systematically favour the status
> quo whenever one side's frequency is countable and the other's is not.** That is
> the asymmetry, and it decides forks quietly and by accident. Whoever settles
> this should decide **which error they would rather make**, not which number is
> larger — because only one of the two numbers exists.

## Recommendation

**B, held weakly, and the weakness is the point.** The verb guard is already in
`CLAUDE.md` for a different reason, so B is a short addition to an existing
paragraph and costs the common case nothing. A is the better guard in isolation
and the worse trade at this loop's frequency.

**But that comparison is exactly the one the paragraph above says cannot be made
on frequency**, so read this as "the cheap half first, and A stays live" rather
than as a settled call. A concrete thing that would move it: **any instance where
the hazard was NOT self-caught** — a wrong conclusion traced back to a stale
binary after the fact, found in a ticket rather than in a confession. One of those
is worth more than ten more self-reports, because it is the only evidence that
can come from the invisible half.

The prose half is the owner's call regardless: `CLAUDE.md` is not edited by
agents, so the sentence goes up as an ask rather than as a commit.
