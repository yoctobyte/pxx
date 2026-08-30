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
summary: "NARROWED 2026-08-30 by frankC, which found the suppression mechanism already exists and had simply not been used -- read the correction block before working this. Original framing: tools/progress.sh ready/next rank a ticket from frontmatter and print slug/prio/track. A GRANT — a coordinator handing one shared file to a named lane for the duration of a campaign — lives in the ticket BODY, so the ranker cannot see it and offers the granted file to every idle agent in that track. working/ does not cover the gap either: a lane that works in slices correctly releases the lock between them. Measured 2026-08-30: the coordinator dispatched frankA onto refactor-a-c-exclusive-lowering while frankC held a written grant on compiler/ir.inc and had four slices landed; both the ranked queue and working/ were clean, and correctly so."
---

# A grant is a lock, and it is invisible to the two things that answer "is this free?"

> ## CORRECTION, and it narrows this ticket considerably (frankC, 2026-08-30)
>
> **The suppression mechanism already exists and I have used it. Check before
> building.** `tools/progress.py:231` defines
> `_NODISPATCH_RE = /NOT DISPATCHABLE|do not claim/i`, matched at line 386 over
> the ticket TEXT. It was added 2026-08-29 for `feature-target-wasm`, after
> `next` printed a paste-ready claim line for a ticket that opens with
> "NOT DISPATCHABLE".
>
> **It is deliberately keyed on that marker and never on `owner:`, and that
> reasoning is sound:** 16 of 332 ranked tickets carry an owner, mostly retired
> session names, so suppressing on `owner:` would hide ~14 real tickets to catch
> one bad dispatch. Do not "fix" that.
>
> The carve-out ticket simply was not using the channel. frankC added a banner
> under its H1 carrying the marker and **measured** the effect rather than
> asserting it: `next --track A` skipped 6 before and 7 after, with the ticket
> live in the queue at p60 — one point under the head — before, and suppressed
> after. Landed `eaf3a9705` + `03fefeb55`, docs only, `compiler/` byte-identical.
>
> **So the residual gap is narrower than this ticket's title.** It is not that
> grants are invisible; it is that the marker is **body text a human must
> remember to write** — a manual mirror of a state the tooling could derive from
> a `granted-to:` field. That is still worth fixing, and the frontmatter proposal
> below stands, but it is an ergonomics fix on a working mechanism, not a missing
> mechanism.
>
> **One thing a purely mechanical fix will not cover**, and frankC flagged it: the
> banner is doing a second job. This ticket's own slice plan lists slices 2-5, all
> arms, so a cold reader who reaches the plan sees four slices to go. The marker
> suppresses the *dispatch*; only the prose corrects the *impression*. Whoever
> takes this should decide whether a derived grant field is also supposed to
> annotate a stale plan, or whether that stays a human's job.


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
