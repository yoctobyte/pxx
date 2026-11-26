---
slug: feature-p-date-and-time-include-macros-in-utc
title: "{$I %DATE%} and {$I %TIME%}: implement them, in UTC"
track: P
prio: 30
type: feature
status: backlog
created: 2026-11-26
found-by: owner decision, filed by claude-dupwt
owner: ""
blocked-by: []
summary: "UNBLOCKED by the owner 2026-11-26: 'localisation a solved issue but you can keep utc for now'. %DATE%/%TIME% are refused today (bug-p-compile-time-info-macros-are-not-implemented-and-silently-yield-zero) because local-vs-UTC was undecided. Decision: UTC. Needs a host clock on both build paths plus civil-from-days. fpc's are local time, so the strings can differ from fpc's by the zone offset; that is the chosen difference. SOURCE_DATE_EPOCH winning for reproducible builds is still open and would be the natural second step."
---

# %DATE% and %TIME% in UTC

The refusal and its reason are in
`done/bug-p-compile-time-info-macros-are-not-implemented-and-silently-yield-zero.md`.
Format as fpc: `%DATE%` is `YYYY/MM/DD`, `%TIME%` is `HH:MM:SS`. Test with a
fixed clock (or SOURCE_DATE_EPOCH, if that is done in the same change) so the
expected output is stable.
