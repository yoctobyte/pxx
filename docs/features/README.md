# Feature tracking

Lightweight, file-based feature tracker, same shape as [`../bugs/`](../bugs/README.md).
One feature per Markdown file. The **folder is the status** — moving a file
between folders is the only state change.

## Folders (lifecycle)

| Folder | Meaning |
| --- | --- |
| `proposed/` | Idea written up, not started. |
| `working/` | Actively being implemented. |
| `incomplete/` | Landed partially — usable but missing pieces; list the gaps. |
| `crashes/` | Implemented but currently miscompiles/crashes; link the repro or `../bugs/` file. |
| `rejected/` | Decided against (for now). Say why; a `proposed/` idea can also go here. |
| `completed/` | Done and covered by a test. Note the commit and the regression test. |
| `triage/` | Escape hatch: unknown status, check-later, needs-a-human/user decision, idk. Park here, revisit. |

Normal flow: `proposed/` → `working/` → `completed/`. A feature may instead land
in `incomplete/` or `crashes/` (shipped but not done), `rejected/`, or `triage/`.

The point is to keep both a **record** (the file and its git history) and a
**state** (which folder it's in). Duplicate or stale entries may exist — that's
fine; prefer parking to losing information. Re-organize or simplify the folders
later if they stop fitting. This is an agentic system: there is no separate
index — agents keep written status in the usual docs (`../project-state.md`,
`../todo.md`) as they already do.

## File convention

- Name: `feature-short-slug.md` (a stable slug; no date prefix, since features
  are named by what they are). The name does not change when the file moves.
- Start with a `#` title, then `**Status:**` and a one-line summary.
- Capture: motivation, intended surface (syntax/CLI/dialect), and acceptance
  (what test proves it).
- When moving to `completed/`, append `## Done`: commit hash + regression test.
- When moving to `crashes/` or `incomplete/`, link the blocking `../bugs/` file
  or list the missing pieces.

## How agents use it

- New feature idea: drop a file in `proposed/`.
- Starting it: `git mv` to `working/`.
- Shipped but broken/partial: `git mv` to `crashes/` or `incomplete/` and link
  the bug.
- Done with a test: add `## Done` and `git mv` to `completed/`.

Docs only — adding/moving these does not touch compiler source, so they skip the
self-host gate.
