---
track: T
prio: 40
type: bug
summary: "A ticket's `- **Status:** working` body line drifts from the folder that actually holds it, and `progress.sh check --strict` says nothing. Twenty tickets had claimed `working` while working/ was empty — nine of them in backlog/unfinished, where it falsely signals a live lock."
---

# `progress.sh check` does not notice a Status line that contradicts the folder

- **Type:** bug — Track T (tooling). Files: `tools/progress.py` / `progress.sh`
  (`check`).
- **Found:** 2026-08-07, cleaning up after the v246 pin.

## Measured

With `devdocs/progress/working/` **empty** — so no ticket holds a live lock —
twenty tickets carried `- **Status:** working` in their body:

| folder | count | matters? |
| --- | --- | --- |
| `backlog/` | 6 | **yes** — reads as "someone is on this" |
| `unfinished/` | 3 | **yes** — same |
| `done/` | 10 | no — archived record |
| `rejected/` | 1 | no — archived record |

`tools/progress.sh check --strict` reports 555 hygiene findings and **none of
them is this**, which is exactly why it drifted: nothing was watching.

The nine live ones were corrected by hand. `done/` and `rejected/` were left
alone deliberately — CLAUDE.md's rule is that a finished record is history and
rewriting it falsifies what a past session actually did.

## Why it is worth a check rather than a one-off sweep

The folder IS the lock (`working/` = an agent is actively on it), so the body line
is duplicated state and will drift again the moment someone edits one and not the
other. A stale `Status: working` on a backlog ticket is a coordination cost: an
agent scanning for work can read it as claimed and skip real work — the opposite
of what the ranked queue is for.

## Suggested fix

In `check`, for every ticket outside `done/`, `rejected/` and `decided/`, compare
the `- **Status:** X` line against the containing folder and report a mismatch.
Cheap, and it makes the sweep unnecessary next time.

Two design calls worth making explicitly rather than by accident:

1. **Do not auto-rewrite.** `claim` / `resolve` already move files; having `check`
   silently edit ticket prose would make it a mutating command, which it is not
   today.
2. **Consider dropping the body line entirely** and letting the folder be the
   only source of truth — `board-md` can render the status from the path. That
   removes the class of bug instead of policing it, and is probably the better
   answer if nothing reads the body line programmatically.

Prio 40: cosmetic-adjacent, no wrong code comes out of it, but it is a small
recurring drag on exactly the queue mechanism every lane depends on.

## Gate
`tools/progress.py --tier full` (T's own gate) plus a scratch board where a
ticket is moved without its Status line being touched, and `check` flags it.
