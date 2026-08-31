---
track: T
prio: 45
type: feature
blocked-by: []
created: 2026-08-31
summary: "Prio propagates only down declared blocked-by: edges, so a ticket that is upstream of a family it was filed AFTER can never inherit their priority. Measured 2026-08-31: `shr` produced ten tickets, eight closed individually over two months priced 30-60, while the one describing their shared cause sat at prio 20 — the lowest of all ten. Add a scan that groups open AND closed tickets by shared construct tokens and flags a cluster whose members were fixed one at a time."
---

# Detect ticket clusters that share a construct

## The measurement

`shr` has produced **ten** tickets. Eight closed individually between
2026-06-26 and 2026-08-25 at prio 30-60; two open. The one describing the
shared cause — `bug-a-shr-reaches-the-ir-spelled-as-tkident` — sat at **prio
20**, below every symptom it produced, until it was repriced by hand on
2026-08-31.

**Nobody mispriced anything.** Prio propagates down `blocked-by:` edges, and
seven of the eight symptoms were filed *before* the cause ticket existed, so
they could never have declared an edge to it. The ranker reads one ticket at a
time; it has no aperture for the shape of a pile.

This is the same blind spot as `root-cause-over-microfix.md`'s rule — *count how
many mechanisms serve the one concept; two is a smell, three is a design flaw* —
except that doc asks a human to notice, and nothing measures it.

## What to build

Group open **and closed** tickets by construct tokens drawn from the slug and
summary (`shr`, `settextbuf`, `widestring`, …; stopword the ticket-type prefixes
`bug-a-`, `feature-`, and the track letters). Report a cluster when several
tickets share a token, and rank the report by **how many members are already in
`done/`** — a construct with many individually-closed tickets is precisely the
one whose root cause is still open and underpriced.

Two outputs, both cheap:

- a `progress.sh` subcommand a human runs when triaging;
- a line in `check`'s output when a cluster crosses a threshold, since that is
  the report anyone already reads.

## The positive control this needs — mandatory

Per CLAUDE.md's *a guard that cannot fail is not a guard, and it prints PASS*:
ship with an asserted case the scan MUST flag. **`shr` is that case and it is
free** — ten tickets, eight closed, the cause at the bottom. If a rewrite of the
scan stops flagging `shr`, it is broken however green it looks.

A second asserted case worth having is a **negative** one: a token that appears
in many tickets and is NOT a cluster (`compiler`, `test`, a track letter). A
scan that flags everything is the same animal as one that flags nothing.

## Scope limit

This RANKS; it does not decide. The output is "these N tickets name one
construct, and M of them are already closed one at a time" — a human or a lane
owner decides whether one is upstream of the others. Do not auto-edit `prio:`;
that field is the human's signal (CLAUDE.md), and a scan that rewrites it
destroys the input it is reasoning from.

## Explicitly NOT the fix that was proposed first

The trigger for this was a proposal to sometimes rank **oldest-first** to flush
stale tickets. Measured the same day and it does not hold: of the 60 oldest
ranked tickets the median prio is **32** against **40** for the whole set, only
9 are at prio >= 55, and all three tickets found stale this week were created
**2026-08-30 — one day old**. Staleness tracks *recency and activity*, not age,
because at ~1900 commits/day a ticket about code under active edit goes stale in
hours while an old one is old precisely because nothing has touched that code.
Recorded here so the idea is not re-proposed from intuition; the separate
one-time triage of the oldest 60 (to reject or reprice, not to work) is still
worth doing and is a different job.
