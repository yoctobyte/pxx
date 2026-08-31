---
slug: bug-t-a-campaign-umbrella-has-no-safe-status-to-sit-in
track: T
prio: 45
type: bug
status: backlog
found: 2026-08-30
found-by: frank-optimize-b4 (surfaced), frank-coordinator (measured)
blocked-by: []
summary: "A container ticket for an active campaign has nowhere correct to live. working/ is a per-agent live LOCK, and an umbrella held there for the length of a campaign is a lock that never clears; every other status ready/next scans is claimable, so parking it invites a second agent onto files the campaign owns. The status vocabulary has no term for 'this is a container, not a unit of work'."
---

# A campaign umbrella has no safe status to sit in

## How it surfaced

frank-optimize-b4, holding the `-O3` W1 campaign, was asked why it held two
`working/` entries. Its answer was correct and is the bug report:

> *The umbrella is what announces `ir_codegen.inc` ownership, and parking it would
> put it back in `unfinished/`, which `ready`/`next` **do** scan — recreating exactly
> the dispatch problem you caught an hour ago. A container ticket for an active
> campaign has nowhere safe to sit except `working/`.*

Both halves are true, which is what makes it structural rather than a mistake:

| status | why the umbrella cannot sit there |
| --- | --- |
| `working/` | a **live lock**, per-agent, meant to be short. An umbrella sits for the length of a campaign, so the lock never clears and every staleness heuristic reads it as abandoned |
| `unfinished/` | **scanned by `ready`/`next`** — a second agent gets dispatched onto the campaign's own files |
| `backlog/`, `urgent/`, `backlog_new/` | same, and ranked higher |
| `blocked/` | not scanned, but a false claim: nothing blocks it |
| `done/` | false while slices remain |

## Measured, 2026-08-30

Of 4 tickets in `working/`, **one is a campaign container** —
`feature-opt-o3-register-pressure`, 77 lines matching umbrella/campaign/slice
vocabulary, versus 0 and 2 for the others. So this is **one instance today and a
recurring shape**: Track O has a campaign now, S is becoming one, M is planned as
one. The letters for work-tags (O, S, M) exist precisely to make campaigns visible,
and the status vocabulary was never extended to match.

## The gap in one line

`status` conflates **"is someone on this"** with **"is this a unit of work"**, and a
container answers *yes* and *no*. Nothing in the vocabulary can say the second thing.

## Options (do not pick one without the owner or a T decision)

1. **A `type: umbrella` (or `container: true`) frontmatter field that `ready`/`next`
   annotate rather than rank** — precedent exists: the ranker already prints
   `[!! DO NOT CLAIM — the ticket says so]` and `[parked — re-claim, do not
   duplicate]`, so the display path for "visible but not claimable" is already built
   and this is a new reason, not a new mechanism. Cheapest, and keeps the umbrella
   in a scanned status where it stays visible.
2. **A `campaign/` folder** unscanned like `float/`. Clean, but adds a folder and
   splits campaign tickets from their lane's queue — and `float/`'s own lesson is
   that unscanned means genuinely invisible, which is right for parked float work
   and wrong for a live campaign.
3. **Leave it in `working/` and teach the staleness checks about it.** Least change;
   keeps a permanent entry in the one folder whose whole meaning is "short-lived".

Recommendation: **(1)**. It reuses the annotation path, needs no folder, and makes
the container's status honest rather than a workaround an agent has to explain each
time it is asked.

## Note

Do **not** pair this with a "ticket prose states a prio that disagrees with
frontmatter" check. That was proposed the same night, from a real instance, and
measured across all 380 ranked + working tickets: **1 states a prio in prose at
all, and that 1 disagrees.** One finding, ever, is not a check — it is a fix, and
it is applied in this same commit. See face 134a.
