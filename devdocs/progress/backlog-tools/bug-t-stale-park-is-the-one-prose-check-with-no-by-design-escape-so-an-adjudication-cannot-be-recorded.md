---
slug: bug-t-stale-park-is-the-one-prose-check-with-no-by-design-escape-so-an-adjudication-cannot-be-recorded
track: T
type: bug
prio: 45
status: backlog
found: 2026-09-06
found-by: frankH raised the residual; measured and filed by frank-coordinator
owner: ""
blocked-by: []
title: "STALE-PARK has no memory of having been answered, and it is the only prose check that does not"
summary: "MEASURED 2026-09-06 in `tools/progress.py`. Three of the four prose/citation checks carry a by-design escape a reader can write into the body -- `DANGLING LINKS BY DESIGN` (1868), `PROSE EDGES BY DESIGN` (2135), `DANGLING SHAS BY DESIGN` (2621, and the emit path TELLS you to add it, twice). STALE-PARK has NONE: greps for `STALE PARK BY DESIGN` and `PARK BY DESIGN` both return 0. `PARK-CONDITION-REWRITTEN` is a REFINEMENT of the hit, not an escape from it. So an adjudicated park re-reports forever, and the cost falls on exactly the tickets that are written well: prose that cites landed work BY NAME near a phrase like `blocked` is what a good write-up looks like, so the better the park, the more reliably it re-fires. Live case, and it cuts BOTH ways: `feature-dynamic-compiler-tables` was adjudicated in its own body at line 341 on 2026-08-30 and re-reported on its SECOND run -- but on re-reading, the slug that note dismissed as `a pointer, not a blocker` (`feature-opt-dynarray-grows-in-place`) has LANDED since, as has `feature-emission-size-dce`, so the second firing was a TRUE hit and the note was stale in the direction that mattered. The check was wrong about BLOCKING and right about STALENESS, on this report's own worked example. DO NOT copy the other three escapes verbatim -- a park's resume condition genuinely CAN become met later, so a blanket suppression would hide a true hit permanently. The escape must record WHICH resolved slugs were adjudicated, so a newly-resolved citation still fires."
---

# STALE-PARK cannot be told it was already answered

## The measurement

`tools/progress.py`, four checks that read prose or citations:

| check | by-design escape | line |
| --- | --- | --- |
| dangling links | `DANGLING LINKS BY DESIGN` | 1868 |
| prose-edge-not-in-frontmatter | `PROSE EDGES BY DESIGN` | 2135 |
| dangling shas | `DANGLING SHAS BY DESIGN` | 2621 — and the emit path names it at 2697 and 2715 |
| **STALE-PARK** | **none** | — |

`grep -c "STALE PARK BY DESIGN"` and `"PARK BY DESIGN"` both return **0**.
`PARK-CONDITION-REWRITTEN` (2060) is a **sharper reading of the same hit**, not a
way out of it.

## Why the cost falls on the GOOD write-ups

STALE-PARK fires on a park whose prose names a now-resolved slug near a blocking
phrase. **Citing landed work by name, next to an explanation of what it
unblocked, is what a well-written park looks like.** So the check's hit rate is
correlated with write-up quality, and there is no way to bank the reading.

**Live case, and it was corrected the same night — read this before the design
section, because the first version of this ticket got it backwards.**
`feature-dynamic-compiler-tables` adjudicated the report **in its own body**, line
341, dated 2026-08-30:

> *"No resume condition names another ticket: the five resolved slugs here are
> cited landed work, and the one open slug (`feature-opt-dynarray-grows-in-place`)
> is a pointer, not a blocker."*

`blocked-by: []`. It re-reported on its **second** run, and this ticket was filed
describing that as an adjudication paid twice.

**That framing was wrong, and frankH found it by re-reading rather than trusting
the note.** `feature-opt-dynarray-grows-in-place` — *"the one open slug ... a
pointer, not a blocker"* — **is now in `done/`, and so is
`feature-emission-size-dce`.** Both verified 2026-09-06. **Both cited dependencies
landed AFTER the note that dismissed them.**

> **The check was WRONG ABOUT BLOCKING and RIGHT ABOUT STALENESS**, on the very
> ticket this report was filed from.

And it was not bookkeeping: **in-place dynarray growth is what makes that ticket's
geometric doubling amortise**, so the pointer dismissed as not-a-blocker is the
thing that made its conversion pattern cheaper. **The note was stale in the
direction that mattered.**

**This is the evidence FOR the scoped design below, and it is a live case rather
than an argument** — a blanket suppression would have hidden a true hit on this
report's own worked example.

## The design constraint — do NOT copy the other three

A dangling sha is dangling forever, so a permanent marker is sound there. **A
park's resume condition can genuinely become met later**, so a blanket
`PARK BY DESIGN` would suppress a *true* hit permanently — the same
fail-open shape as a false coverage claim, and worse than the noise it removes.

**The escape has to be scoped to what was adjudicated.** Something of the shape
`PARK ADJUDICATED <date>: <slug>, <slug>, ...` in the body, where the check
suppresses only the listed slugs and **still fires when a citation resolves that
is not on the list.** Then a well-written park pays once per newly-resolved
citation instead of once per run, and the record of the reading lives beside the
prose it was about.

## Not urgent, and say so

Nothing is mis-ranked by this. The cost is a recurring read of a report that has
already been answered, paid by the sessions holding the longest-lived tickets.
