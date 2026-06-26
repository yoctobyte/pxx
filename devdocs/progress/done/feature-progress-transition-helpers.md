# Progress transition helpers (`claim` / `resolve`)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-06 (from agents/discussion/progress-tracker.md, Antigravity)

## Motivation

Claiming/resolving a ticket means a `git mv` plus hand edits to `Status:`/`Owner:`
and (on resolve) a Log entry — tedious and easy to get half-done.

## Scope

- `progress.sh claim <slug> <owner>`: `git mv` ticket to `working/`, rewrite
  `Status:` → working, set `Owner:` to the passed value.
- `progress.sh resolve <slug> <commit>`: `git mv` to `done/`, set `Status:` →
  done, append a `## Fix`/`## Done` log line with the commit.

Constraints (from the review):

- **No auto-commit.** Stage the move + edits and stop; the agent writes the
  commit (the claim rule is "mv + Owner in the *same* commit", agent-authored).
- **Owner is an argument, never inferred** — an agent can't reliably discover its
  own identity, and mislabeling violates the AGENTS.md attribution rule.

## Acceptance

`claim`/`resolve` leave a correct, uncommitted working tree (right folder, fields
updated); `progress.sh check` passes afterward; no commit is made by the script.

## Log
- 2026-06-06 — ticket opened from the design review thread.
- 2026-06-22 — resolved, commit 64ac43f.
