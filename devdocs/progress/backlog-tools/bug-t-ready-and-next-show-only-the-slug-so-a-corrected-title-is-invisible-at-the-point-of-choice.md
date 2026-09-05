---
slug: bug-t-ready-and-next-show-only-the-slug-so-a-corrected-title-is-invisible-at-the-point-of-choice
track: T
type: bug
prio: 45
status: backlog
found: 2026-09-05
found-by: frank-coordinator
owner: ""
blocked-by: []
title: "The one field a reader sees when choosing a ticket is the one field that cannot be corrected"
summary: "`ready` and `next` print the SLUG and nothing else descriptive -- no `title:`, no `summary:`. 259 of 598 tickets carry a `title:`, and `progress.py` reads it only in `near`/`dupes` (`_head()`, line 3021) for dedup scoring; it never reaches the queue output. That matters because THE SLUG IS THE CITATION KEY -- `[[slug]]` links and `resolve <slug>` both key on it and THERE IS NO RENAME SUBCOMMAND -- so the one field every chooser reads is the one field the TOOLING gives no way to correct, and the manual cost of correcting it SCALES WITH HOW LONG THE TICKET HAS BEEN USEFUL. Measured: of 6138 ticket slugs, 2432 are cited at least once; median 2 citing files, but 249 slugs are cited by >=5 and 34 by >=10, topping out at 37 (`feature-demo-songformatter-pxx-target`) -- and the heavily-cited ones are the long-lived campaign rows, `feature-pascal-corpus-expansion` at 32 being the current head of `ready --track P`. So the tool fails hardest on exactly the tickets that matter most. Fix: print `title:` under the slug in `ready` and `next` when present, falling back to the first clause of `summary:`. Cheap, no schema change, and it makes a rename unnecessary rather than merely affordable."

---

# `ready` and `next` show only the slug

## The measurement

- **598** tickets carry `slug:`; **259** carry `title:`.
- `tools/progress.py:3021` — `_head()` joins `slug + title + summary`, and it is
  called **only** from `near`/`dupes` (dedup scoring). Nothing else reads `title:`.
- `ready` prints `[p NN] [T] <slug> (unblocks N)`. `next` prints slug, effective
  prio and the path. **Neither prints `title:` or `summary:`.**

So a filer who corrects a ticket's `title:` and `summary:` has corrected two
fields that **no chooser ever sees**, and left untouched the one that every
chooser reads.

## Why it is not merely cosmetic — and the cost is MEASURED, not asserted

**The slug is the citation key.** `[[slug]]` links resolve on it, `claim` and
`resolve` take it, and `progress.sh` has **no rename subcommand**.

A rename is therefore a manual citation sweep, and **its cost is a function of
how long the ticket has been useful:**

| citing files | slugs |
| --- | --- |
| at least 1 | **2432** of 6138 |
| median among those cited | **2** |
| >= 5 | **249** |
| >= 10 | **34** |
| maximum | **37** (`feature-demo-songformatter-pxx-target`) |

**The heavily-cited slugs are the long-lived campaign rows** —
`feature-pascal-corpus-expansion` at **32** is the current head of
`ready --track P`. So:

> **The one field every chooser reads is the one field the tooling gives no way
> to correct, and the tool fails hardest on exactly the tickets that matter
> most.** A day-old row is cheap to rename; the row everybody cites is not, and
> a wrong name on that row does the most damage.

## The measured floor, which is the cheap end of that distribution

`bug-p-a-generic-template-in-a-unit-may-reference-a-non-global-symbol` asserted
the **opposite** of what frankS measured on 2026-09-05 (a generic template body
resolves at the SPECIALIZATION site, so it binds the caller and cannot see its
own unit). frankS renamed it to
`bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site`
in `627be41ed`, having **enumerated the cost rather than estimating it**: zero
citations in code or tests, **one** live ticket body
(`feature-pascal-corpus-fpc-testsuite.md`, updated in the same commit), one
commit message — which this repo explicitly treats as an unmaintained historical
record — and `BOARD.*` regenerate themselves.

**That is the floor, not the typical case**: a row filed the same day, at the
median or below. It does not retire this ticket, because the sweep it needed was
manual and nothing about it scales.

**frankS's own test for when a rename is warranted, recorded here so the next
reader inherits the test and not the precedent** — all three clauses must hold:

1. the slug states something **measured false**, not merely stale;
2. it is **the only field the chooser reads** (which is what this ticket is about);
3. the citation count is **small enough to enumerate** rather than estimate.

**Where any one fails: correct `summary:` and leave the slug alone.** The frozen-slug
default stands.

## The fix, which needs no schema change and no rename

Print `title:` beneath the slug in `ready` and `next` when the field is present;
fall back to the first clause of `summary:` when it is not. The data is already
loaded — `near` reads it today.

**A rename is the expensive alternative and is not required by this fix.**
Whether slugs should be renameable at all is a separate question and should not
hold this up.

## Family

Same shape as an index that disagrees with the record it indexes: the summary
line everyone reads is authoritative *because* it is the only one read, and
correcting the record beneath it changes nothing for the reader. Cf. `BOARD.md`
vs `BOARD-brief.md`, and *"a ticket's `summary` MUST be true — it is the only
part everyone reads"* (CLAUDE.md), which is true of the intent and **one field
off from the mechanism**: at selection time the summary is not shown either.
