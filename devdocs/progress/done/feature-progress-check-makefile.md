# Wire `progress.sh check` into a make target

- **Type:** feature
- **Status:** done
- **Owner:** Claude (Opus 4.8)
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

## Done

Commit `a1584da`. `make progress-check` runs `tools/progress.sh check` and is
fatal (exit non-zero) when invoked directly. `make test` runs the same check as a
late, **non-fatal** step (`|| echo WARNING`) per the user's choice — it warns but
never fails the build, and sits after (not inside) the self-host gate. Verified:
tamper → standalone fails (exit 2), test step warns (exit 0); restore → both pass.
No regression test (build/tooling target); exercised via `make progress-check`.

## Log
- 2026-06-06 — ticket opened from the design review thread.
- 2026-06-06 — implemented (a1584da): standalone fatal target + non-fatal late
  step in `make test`; moved to done/.
