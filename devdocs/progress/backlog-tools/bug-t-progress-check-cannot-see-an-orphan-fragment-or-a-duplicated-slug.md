---
track: T
prio: 45
type: bug
blocked-by: []
summary: "`progress.sh check` validates ticket CONTENT but not the ticket SET: it cannot see a file with no frontmatter, nor one slug present in two ranked folders. Both occurred together on `bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open` — two appends addressed to `backlog/` while the ticket lived in `backlog_new/` created an empty-headed orphan there, and the ranker then offered the slug twice, once complete-but-analysis-free and once carrying all the analysis with no frontmatter. Neither the checker nor the board reported anything."
---

# `progress check` cannot see an orphan fragment or a duplicated slug

Filed 2026-08-29 by frank-coordinator, from its own error. Repaired in the same
push; this ticket is the *guard*, not the repair.

## What happened

Two appends on 2026-08-28 (`f7bf2dfa3`, `04b745294`) were addressed to
`devdocs/progress/backlog/<slug>.md`. The ticket was in `backlog_new/`.

A shell append to a path that does not exist **creates it**. So:

- the appends reported success, and the content was really written;
- the file that received it had **no frontmatter and no body** — the analysis
  arrived at an empty-headed orphan;
- the real ticket never received a word of it;
- and `ready --track A` then listed the slug **twice**, both at p60.

The whole thing survived a day of ranked queues and a board regeneration.

## Why nothing caught it

Both checks are about the ticket SET, and the tooling validates ticket CONTENT:

1. **No frontmatter → not a ticket.** Every real ticket opens `---`. A file in a
   ranked folder that does not is either an orphan or a corruption, and there is
   no legitimate case for it. (The `README.md` in `backlog_new/`, `float/` and
   `experimental/` are the only exempt files and are already distinguishable by
   name.)
2. **One slug, two ranked folders.** `urgent`, `backlog`, `backlog_new`,
   `unfinished` and `blocked` are all scanned. A slug in two of them is
   unresolvable by construction: a worker claiming one leaves the other ranked,
   and the two bodies can differ — here one held the entire analysis and the
   other held none of it.

Both are cheap: a `head -1` per file, and a `sort | uniq -d` over basenames.

## Severity is in the silence, not the frequency

I swept every ranked folder afterwards: **exactly one instance**, and the three
READMEs, which are legitimate. So this is not a widespread corruption and the
ticket is not urgent.

What earns it a prio is that **the failure mode is a ticket that reads as
complete.** The orphan looked like a fully-written analysis to anyone who opened
it; the real ticket looked like a correctly-filed bug to anyone who opened
*that*. Neither one announces that the other exists. A reader lands on whichever
the ranker offered and gets a coherent, wrong picture — the complete-looking one
is missing a measured correction that inverts its central table.

## Suggested shape

Add both to `progress.sh check` as hard failures naming the file. Do **not** try
to auto-merge a duplicate — the repair here required reading both bodies and
deciding what superseded what, which is a judgement call and must stay one.

`check` already fails on an unfinished Track A ticket, so the exit-code contract
and the reporting format both exist; this is two more conditions inside it.
