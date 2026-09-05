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
summary: "`ready` and `next` print the SLUG and nothing else descriptive -- no `title:`, no `summary:`. 259 of 598 tickets carry a `title:`, and `progress.py` reads it only in `near`/`dupes` (`_head()`, line 3021) for dedup scoring; it never reaches the queue output. That matters because THE SLUG IS THE CITATION KEY -- `[[slug]]` links and `resolve <slug>` both key on it and there is no rename subcommand -- so the slug is simultaneously the only text at the point of choice AND the only field nobody can fix. Measured live: `bug-p-a-generic-template-in-a-unit-may-reference-a-non-global-symbol` sits at p55 in `ready --track P` asserting the OPPOSITE of its own measured content (frankS, 2026-09-05: a template body resolves at the SPECIALIZATION site, so it cannot see its own unit). Its `title:` and `summary:` were corrected in the same commit and neither is printed. Fix: print `title:` under the slug in `ready` and `next` when present, falling back to the first clause of `summary:`. Cheap, no schema change, no rename needed."
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

## Why it is not merely cosmetic

**The slug is the citation key.** `[[slug]]` links resolve on it, `claim` and
`resolve` take it, and `progress.sh` has **no rename subcommand** — so correcting
a slug means editing every citation by hand, which is exactly why nobody does it.

> **The only text at the point of choice is the only field that cannot be
> corrected.** Every correction lands somewhere the reader is not looking.

## The live case

`bug-p-a-generic-template-in-a-unit-may-reference-a-non-global-symbol` is **p55
in `ready --track P` right now.** frankS measured it on 2026-09-05 and the
direction is reversed: a generic template body resolves its symbols **at the
specialization site**, so it binds the caller's symbol and **cannot see its own
unit's** — two defects, the second being a refusal of legal code. The ticket's
`title:` says exactly that. **The queue says the opposite**, and a reader who
picks on the slug arrives with an inverted model of the defect before opening
anything.

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
