---
slug: bug-t-36-ranked-tickets-have-no-track-field-and-their-lane-rests-on-the-filename
title: "36 ranked tickets have no `track:` field, so their lane is inferred from the slug and moves silently on a rename"
track: T
prio: 45
type: bug
blocked-by: []
status: low-prio
owner: ""
created: 2026-08-30
found-by: frankC (found one instance on the csmith ticket), swept by frank-coordinator
summary: "tools/progress.sh infers a track from the slug when frontmatter does not declare one. It infers CORRECTLY today -- this is latent, not live -- but the declaration then rests on the filename, so renaming a slug moves the ticket's lane with no diff that says so. Measured across urgent/backlog/backlog_new/unfinished/blocked: 36 of the ranked set carry no track: line at all. check does not report it."
---

# The measurement

`grep -L '^track:'` over the five ranked folders (`urgent`, `backlog`,
`backlog_new`, `unfinished`, `blocked`) returns **36 tickets**. Every one is
ranked and dispatchable today, and the ranker prints a lane letter for each by
inferring from the slug.

The inference is right. `feature-c-csmith-differential-fuzzing` prints `[C]`, and
frankC verified that is the correct lane by reading the ticket's own ownership
section rather than trusting the letter. So **nothing is mis-routed right now**.

# Why it is still a defect

CLAUDE.md ends its track section with the rule this violates, and names the
incident that produced it:

> **Declare a track in frontmatter** — that is what the ranker reads.
> (`meta-track-w-collision-windows-vs-website`: two campaigns claimed W
> simultaneously for months because one declared it in frontmatter and the other
> in prose, so neither side's grep saw the other.)

A lane that rests on a filename has three failure modes, none of which produce a
diff a reviewer would question:

1. **A rename moves the lane.** `feature-c-*` → `feature-cfront-*` and the ticket
   silently leaves Track C.
2. **A new slug prefix quietly captures tickets.** The inference table is a
   prefix map; adding a prefix re-lanes everything matching it.
3. **The letter cannot be contradicted.** A ticket whose body says "this is
   Track A work" and whose slug says `feature-b-` prints `[B]`, and the prose
   loses without a warning — the exact shape of the W collision.

# What to build

`tools/progress.sh check` already reports `PROSE-EDGE-NOT-IN-FRONTMATTER` on the
principle that *the ranker reads frontmatter and nothing else* (`944a7fccb`).
This is the same principle applied to the track itself, and check is silent on it.

- Add a **`MISSING-TRACK`** aperture: ranked folders only, reporting the slug, the
  letter that WOULD be inferred, and that a rename would move it. Naming the
  inferred letter matters — it makes the fix a one-line confirmation rather than a
  research task.
- Consider whether `next`/`ready` should mark an inferred letter visually
  (`[C?]`), so a dispatcher can see the difference between declared and guessed.
  That is a judgement call for whoever takes this; it costs a column and buys
  a distinction the coordinator currently cannot make.

# What NOT to do

**Do not bulk-add `track:` to all 36 in one sweep.** The inference is correct
today, so a sweep buys no correctness and risks 36 silent mis-declarations if any
one is guessed wrong — trading a latent hazard for a live error. Declare the track
when you touch a ticket for another reason, the way frankC did on the csmith
ticket (one line, ranker output verified unchanged). The checker is what makes
that habit reachable.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
