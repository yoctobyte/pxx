---
track: P
prio: 45
type: bug
blocked-by: []
status: rejected
summary: "DUPLICATE of bug-a-lowercase-resolves-to-two-different-routines-depending-on-the-seed, filed 2026-08-28. Tombstone kept so citations resolve; the surviving ticket carries this one's analysis."
owner: ""
---

# DUPLICATE — see `bug-a-lowercase-resolves-to-two-different-routines-depending-on-the-seed`

Filed 2026-08-29 by the coordinator from a fresh `tools/forwardlint.py` run. The
same finding had been filed **the previous day**, by frankwasm from the same
tool — and that ticket's frontmatter records it as *verified by
frank-coordinator*. A previous session of this role had already confirmed it and
the current session had lost that state.

**Not deleted.** A stale reference should resolve to a tombstone rather than to
nothing (convention set by frank-optimize-b4 the same evening, for the
`EmitLoadVarA64` pair). Everything of substance was merged into the surviving
ticket; nothing here is unique.

**The lesson, since it is the second duplicate filed on this board in one
evening:** rule 9 — *the check gets spent on the candidate you doubt, not the one
you like.* A lint NOTE that is new **to this session** reads as a new finding,
and `grep` for the slug before filing costs one command. `progress check` now
carries a `NEAR-DUP` scan for exactly this, calibrated on the board that
contained this pair.
