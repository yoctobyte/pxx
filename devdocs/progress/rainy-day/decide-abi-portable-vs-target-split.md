---
prio: 60
type: decide
track: U
---


## Status 2026-07-20 — deliberately left unshaped

Reviewed with the user during the decide- sweep. It has no options table, and
unlike the others it is not yet a fork you can answer — it needs design work
before it becomes a decision. The user's call: **leave it open, shape it
later**, at prio 60 unchanged.

Not an oversight, and not stalled on anyone: whoever next has the context for
where the portable/per-target line should sit in the IR should write the
options table first, then it can be decided like the rest.

---

## POSTPONED — 2026-08-01 (user), with a shaping hint

> "2 dito. it's likely a per-library source (can we compile vs mimic)"

Still not a fork you can answer — but that is the first concrete framing anyone
has put on it, and it is worth keeping, because it suggests the portable /
per-target line may not be a single global cut at all.

The reading: for each library, the question is **can we COMPILE the real thing,
or must we MIMIC it?** Where the real source compiles, the target-specific work
is whatever the ABI genuinely requires. Where it must be mimicked, the boundary
is wherever our reimplementation stops matching. That makes the split a
per-library property with a portable core, rather than one line drawn through
the IR — which is how the ticket had implicitly been framed.

Whoever shapes this should write the options table around that, then it can be
decided like the rest.

**Bookkeeping:** the 2026-07-20 note recorded "at prio 60 unchanged", but the
file had no frontmatter at all, so it was defaulting to 50 and showing blank in
`progress.sh ready`. Frontmatter added to match the decision already on record —
not a new priority call.

## 2026-08-08 — moved to rainy-day/ so it stops ranking as READY

Postponed by the user twice — *"leave it open, shape it later"* (2026-07-20) and
POSTPONED with a shaping hint (2026-08-01) — yet it stayed in `backlog/` and
therefore ranked **first** in `ready --track U` at prio 60, every time anyone
looked. It was surfaced to the user again on 2026-08-08 as an open question it is
not.

Nothing about the decision changes: it still needs an options table written by
whoever next has the context for where the portable/per-target line sits in the
IR, and the shaping hint stands. It is simply not AWAITING an answer, so it
should not be in the queue of things awaiting one.

**Rule this makes concrete: postponed is a LOCATION, not a note.** A decision the
user has deferred belongs in `rainy-day/`; leaving it ranked turns the U queue
into noise and costs the user the same question twice.
