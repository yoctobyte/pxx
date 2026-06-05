# On-demand `BOARD.md` kanban grid

- **Type:** idea
- **Status:** done
- **Owner:** Claude (Opus 4.8)
- **Opened:** 2026-06-06 (from agents/discussion/progress-tracker.md, Antigravity)

## Motivation

`progress.sh board` already prints per-status counts. A visual grid (ticket names
laid out by status column) would be a nicer **human** view.

## Scope (if adopted)

- `progress.sh board-md`: emit a Markdown table / kanban grid of all tickets by
  status.
- Output to a **gitignored** `docs/progress/BOARD.md` — generated on demand,
  never committed (a checked-in board drifts and causes merge conflicts; the
  filesystem is the real index).

## Why idea, not feature

Low value for agents (`board` covers them); build only when a human actually
wants the grid. Decide before scoping.

## Done

Implemented in commit `5b020a7` as `tools/progress.sh board-md` →
`docs/progress/BOARD.md` (gitignored, on-demand). No regression test — tooling
script, exercised by running it; `tools/progress.sh check` keeps the board valid.

## Log
- 2026-06-06 — ticket opened from the design review thread.
- 2026-06-06 — implemented (5b020a7), moved to done/.
