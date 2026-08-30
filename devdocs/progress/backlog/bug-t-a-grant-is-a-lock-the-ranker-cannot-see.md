---
slug: bug-t-a-grant-is-a-lock-the-ranker-cannot-see
title: "A GRANT is a second kind of lock, and neither ready/next nor working/ shows it"
track: T
prio: 55
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-08-30
found-by: frankA (refused a dispatch onto a granted file), filed by frank-coordinator
summary: "tools/progress.sh ready/next rank a ticket from frontmatter and print slug/prio/track. A GRANT — a coordinator handing one shared file to a named lane for the duration of a campaign — lives in the ticket BODY, so the ranker cannot see it and offers the granted file to every idle agent in that track. working/ does not cover the gap either: a lane that works in slices correctly releases the lock between them. Measured 2026-08-30: the coordinator dispatched frankA onto refactor-a-c-exclusive-lowering while frankC held a written grant on compiler/ir.inc and had four slices landed; both the ranked queue and working/ were clean, and correctly so."
---

# A grant is a lock, and it is invisible to the two things that answer "is this free?"

## What happened

`refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed`
carries a section headed **"GRANT — compiler/ir.inc to frankC (Track C) for this
carve-out, 2026-08-29"**, written by the coordinator, with five conditions and an
expiry of *"when this ticket resolves, or when frankC reports the slot released —
whichever is first."*

On 2026-08-30 the coordinator dispatched **frankA** onto that same ticket, having:

- read `tools/progress.sh ready --track A`, which printed it as `[p 60] [A]` with
  its summary, and
- checked `devdocs/progress/working/`, which was empty.

Both checks were clean. **Both were also correct.** frankC works the carve-out in
slices (`52ef661e6`, `72de20420`, `aef5f27e3`, `06c3cd966` — four landed,
`compiler/cir.inc` at 379 lines) and releases the ticket lock between slices,
which is the behaviour the lock model asks for. The grant is what spans the gaps,
and the grant is prose in the body.

frankA refused the dispatch before opening the file, from `git log` and
`ListAgents` alone. Nothing was edited. The cost this time was two messages.

## Why the near-miss was worse than a merge conflict

frankA's own framing, and it is the right one: the collision would not have been
two edits to one file. It would have been **two sessions applying different
carve-out charters to one file** — frankC's written into its commit messages, and
frankA's improvised on the spot. That merges cleanly and is discovered later, by
which time both charters are half-applied.

There is a second cost specific to this campaign. Slice 1b's census had to be
corrected by `fe78e0cb9` ("the caller census read PROSE as evidence, in both
directions"), and slice 1c is titled "the candidate a COMMENT had hidden". A
second agent re-running that inventory from scratch would likely have reproduced
the exact bug frankC had already fixed in it.

## The shape

This is the same class as the note already in CLAUDE.md about resuming parked
work: *a lock is a claim about the present made by an action in the past, and
nothing re-asserts it*. The grant generalises it — a grant is a claim about a
FILE rather than a ticket, made once, in prose, in a document the ranker reads
only the frontmatter of (`PROSE-EDGE-NOT-IN-FRONTMATTER`, `944a7fccb`, is this
same lesson learned for a different field).

## What would fix it

The ranker reads frontmatter and nothing else, by design, so the fix is to put
the grant where the ranker looks:

- a frontmatter field — `granted-to: frankC` / `grant-files: [compiler/ir.inc]`,
  with an expiry — set when the coordinator writes the grant;
- `ready`/`next` print it inline and loudly, the way they already print
  `[!! DO NOT CLAIM — the ticket says so]` and `[parked — re-claim, do not
  duplicate]`; those two precedents are the model, and a grant is strictly more
  dangerous than either because it names a FILE other tickets also touch;
- `progress.sh check` warns when a grant is older than its expiry condition can
  be evaluated, so a stale grant does not silently hold a file forever.

Two judgment calls left to whoever takes it: whether a grant should also block
`next` from returning the ticket at all (probably yes for a different track,
probably no for the grantee), and whether the file list should be checked against
what the claiming agent actually touches (probably out of scope — that is a hook's
job, not the board's).

## Note on ownership

Filed to **T** because `tools/progress.sh` is T's by practice — its recent history
is `feat(T)` / `feat(tools)` (`944a7fccb`, `1c60a8214`, `e59189d0c`,
`0a87cb4ce`, `1ff974d9c`). If T reads the board tooling as outside its charter,
re-file to A rather than closing it; the defect is real either way.
