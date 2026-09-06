---
slug: bug-t-a-stale-blocked-by-in-a-BACKLOG-folder-is-outside-every-aperture
title: "18 ranked tickets are gated on a ticket that has closed, and no check looks there"
track: T
type: bug
prio: 50
status: backlog
owner: ""
created: 2026-09-06
found-by: frankH (one instance, while fixing the exception-escape leak); frankuser (census)
blocked-by: []
summary: "`progress.sh check`'s STALE-PARK aperture covers `unfinished/`, `blocked/` and `working/`. It does NOT cover the per-lane backlogs, which is where open unclaimed work now lives -- so a `blocked-by:` naming a ticket that has since closed reads as GATED to every human and every agent, forever, and nothing reports it. Census 2026-09-06 at da2fea0fd: 18 distinct ranked non-umbrella tickets carry 20 such edges, across backlog-core (6), backlog-pascal (3), backlog-libs (3), backlog-nilpy (2), backlog-windows (2), backlog-tools (1) and unfinished/ (2). LIVE COST, measured not supposed: frankH found the first instance because frankA had told them an hour earlier that the exception-escape leak was blocked on `decide-does-raise-of-an-existing-object-transfer-ownership` -- which was in `done/`, settled for option (a) by the FPC oracle. The fix took an afternoon once the belief was removed. APERTURE NOTE THAT MUST SURVIVE ANY FIX: umbrella tickets legitimately name closed tickets -- membership is an EDGE and a closed member is PROGRESS, not staleness -- and 19 such edges exist. A check that reports those is a check people turn off."
---

# A stale `blocked-by` in a backlog folder is outside every aperture

## The gap

`check` has a STALE-PARK arm. Its aperture is `unfinished/`, `blocked/` and
`working/` — the folders where parked work lived when it was written. **Open
unclaimed work now lives in the per-lane backlogs**, and those are not scanned.

A `blocked-by:` edge naming a ticket that has since closed therefore:

- reads as **gated** to anyone who opens the ticket,
- reads as **gated** to anyone told about it by a peer,
- is invisible to `check`,
- and never expires.

**It does not error. It answers.** The ticket looks correctly parked.

## The live cost, measured

frankH fixed `bug-a-an-exception-that-escapes-its-handler-or-is-bare-re-raised-still-leaks-its-object`
on 2026-09-06 — 2001 live per 1000 trips down to 3, `d37ee1734`. Its
`blocked-by` named `decide-does-raise-of-an-existing-object-transfer-ownership`,
**which is in `done/`**, settled for option (a) by the FPC oracle: FPC frees a
raised object it did not construct, so `raise` transfers ownership
unconditionally.

**The belief had propagated.** frankA had told frankH an hour earlier that the
row was blocked on that decision. Neither had reason to re-check; the frontmatter
said so and nothing contradicted it.

## The census

At `da2fea0fd`, resolving every `blocked-by` slug to its folder:

| folder | tickets |
| --- | --- |
| backlog-core | 6 |
| backlog-pascal | 3 |
| backlog-libs | 3 |
| backlog-nilpy | 2 |
| backlog-windows | 2 |
| backlog-tools | 1 |
| unfinished/ | 2 |

**18 distinct tickets, 20 edges.** Two of the `backlog-pascal` rows
(`bug-p-thirteen-builtin-type-names...`, `feature-p-the-booleannn-family...`)
went stale *today*, when the type-identity fork was decided — so this accrues
continuously and is not a historical backlog.

## THE APERTURE NOTE, and any fix that ignores it will be turned off

**Umbrella tickets legitimately name closed tickets.** Membership is an EDGE, not
a folder, and a closed member is **progress** — it is how an umbrella records
what has been delivered. There are **19** such edges and every one is correct.

A checker that reports them produces 39 findings of which 19 are noise on the
first run, which is how a check stops being read. **Exclude `type: umbrella` and
`backlog-umbrella/`, and say in the output that the exclusion is deliberate**, or
the next person will "fix" the exclusion.

## Suggested shape

Widen the existing STALE-PARK arm's aperture to every ranked folder rather than
adding a second checker — a second checker is a second copy of the resolution
logic, and the two will disagree. The resolution itself already exists: `check`
resolves slugs to tickets today for DANGLING-LINK.
