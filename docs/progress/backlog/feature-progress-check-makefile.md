# Wire `progress.sh check` into a make target

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from agents/discussion/progress-tracker.md, Antigravity)

## Motivation

`tools/progress.sh check` validates the board (dangling slugs, cycles,
ownerless `working/`, commit-less `done/`) but nothing runs it automatically.

## Scope

- Add a `make progress-check` target invoking `tools/progress.sh check`.
- Keep it **out of** the self-host gate (`bootstrap`/`fpc-check`). The board is
  docs-only; AGENTS.md lets docs/tooling changes skip the byte-identical gate, so
  a board typo must not block a compiler fix.
- Optionally call it as a late, clearly-labeled step in `make test`.

## Acceptance

`make progress-check` passes on a clean board, fails on an injected
dangling/cycle, and does not couple the compiler build gate to board state.

## Log
- 2026-06-06 — ticket opened from the design review thread.
