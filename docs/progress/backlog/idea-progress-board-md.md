# On-demand `BOARD.md` kanban grid

- **Type:** idea
- **Status:** backlog
- **Owner:** —
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

## Log
- 2026-06-06 — ticket opened from the design review thread.
