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
