---
track: T
prio: 40
type: bug
summary: "A ticket's `- **Status:** working` body line drifts from the folder that actually holds it, and `progress.sh check --strict` says nothing. Twenty tickets had claimed `working` while working/ was empty — nine of them in backlog/unfinished, where it falsely signals a live lock."
status: done
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

## DONE 2026-08-14 — check reports it; design call 2 deliberately not taken

`check` now compares the `- **Status:** X` body line against the containing
folder. Three real drifts on the live board, all corrected:

| ticket | folder | claimed |
|---|---|---|
| `bug-pascal-uses-is-transitive` | `blocked/` | working |
| `feature-real-dynlib-loader` | `unfinished/` | working |
| `feature-signal-siginfo-ucontext` | `backlog/` | working |

### The hard part was what NOT to report

A naive folder-vs-line comparison finds **179** mismatches on this board, of
which **3** matter. The other 176 are two kinds of false positive, and burying
three findings under them is precisely how this drifted while `check --strict`
was already printing 555 things:

- **prose, not a status.** The line frequently carries a sentence —
  `Status: documented, not fixed`, `Status: harness`. Only a first word that is
  itself a folder name counts.
- **accurate parking.** 14 tickets in `experimental/` say `Status: backlog`,
  which is true: they *are* backlog work, parked as experimental. Not a
  contradiction.

So it fires only when the claim is **lock-ish** — `working` or `urgent`, the two
a reader acts on — in either direction. `backlog/` saying `unfinished` is
cosmetic and stays silent.

Archives (`done/`, `rejected/`, `decided/`) are exempt, per CLAUDE.md: a
finished record is history and rewriting it falsifies what a past session did.

### Design call 1 honoured, design call 2 not taken

**Not auto-repaired.** `check` stays read-only; `claim`/`resolve` are what move
tickets, and having `check` edit prose would make it mutating. Asserted in the
devtest.

**The body line was NOT dropped.** The ticket suggested letting the folder be
the only source of truth. Tempting, and it would delete the class rather than
police it — but the line is load-bearing prose in a lot of tickets (`Status:
documented, not fixed`, `Status: pre-existing`, `Status: harness`), so removing
it mechanically would destroy real information. That is a separate, larger
cleanup and not obviously worth it now that the drift is caught automatically.

### Gate

`tools/devtest_status_drift.py` — 12 checks against a scratch board.

One trap worth recording: `progress.py` takes its ROOT from
`Path(__file__).parents[1]`, **not from cwd**, so running it with `cwd=<scratch>`
silently checks the REAL board. The first version of this devtest did exactly
that, and every negative case passed vacuously against a board that had just
been cleaned — worse than no test. The script is now copied into the scratch
tree.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
