---
slug: bug-the-queue-makes-filing-a-duplicate-the-path-of-least-resistance
track: A
prio: 70
status: backlog
---

# The queue makes filing a duplicate the path of least resistance

## The evidence, which is a measurement and not a worry

`feature-t-gate-quick-should-smoke-the-pinned-compiler` and
`bug-t-gate-quick-cannot-see-a-broken-pinned-rtl` are **the same defect filed
twice**, four days apart, both at `prio: 65`, by two different agents, from two
genuinely different incidents (`PXXVariantErrorHook` and `PXXNilRefHook`).
Neither cites the other. Both are now closed by one change (`1cc54252e`).

Nobody detected the duplication for four days. It surfaced only because
`tools/progress.sh next --track T` happened to hand one agent the second ticket
immediately after it closed the first. Had the ranking put anything between
them, both would still be open, and a third incident would have produced a third.

## Why this is a triage bug and not a tidiness bug

The project owner's loudest standing complaint is that **triage is the
bottleneck** -- *"I see low-prio tickets that I would rank highest. And vice
versa."* A queue in which filing a duplicate is the cheapest available action
manufactures its own backlog, and does it in the way that damages ranking most:
one real problem appears as N items of middling priority rather than one item of
high priority. Two independent rediscoveries in four days is evidence a seam
matters; split across two tickets, it read as two ordinary 65s.

Note the failure is not that the filers were careless. Each did the right thing
from a real incident. **Nothing in the workflow would have told either of them
the other ticket existed** -- `next` and `ready` rank, they do not search, and a
filer with a fresh incident has no reason to grep the backlog for a symptom
described in someone else's words.

## What to look at

- A `progress.sh` path that runs *at file time* over open ticket titles/bodies
  and surfaces near-neighbours -- the cost is one prompt to the filer, and the
  filer is the only person holding enough context to judge the match.
- Whether `resolve` should ask the same question in reverse: this change closed a
  ticket, does it also close any of these?
- Duplicate pairs that already exist in the backlog. This one was found by luck;
  it should not be the only one.

Deliberately not proposed here: any scheme that ranks or auto-merges without a
human-or-agent judgement in the loop. The point is to make the existing
information *reachable at the moment of filing*, not to guess.

## Provenance

Found by the Track T agent while closing both tickets in one change, 2026-08-26.
Filed by the coordinator; T was told not to spend cycles on it.
