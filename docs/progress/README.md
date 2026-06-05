# Progress tracker

One unified, file-based board of **tickets** — bugs, features, tests, chores.
One ticket per Markdown file. A ticket is an appendable, editable record: keep a
running `## Log`, never rewrite history away.

Two axes:

- **Status = folder.** Moving the file (`git mv`) is the only state change.
- **Type = filename prefix.** So a single folder of mixed work stays filterable.

This replaces the older split `docs/bugs/` and `docs/features/` folders.

## Status folders

| Folder | Meaning |
| --- | --- |
| `backlog/` | Captured, not prioritized. New tickets land here (or `urgent/`). |
| `urgent/` | Prioritized, do soon. |
| `working/` | Claimed and in progress. Set `Owner` so agents don't collide. |
| `blocked/` | Needs a user decision, external input, or can't-reproduce. Say why. |
| `done/` | Completed/fixed. Note the commit and the regression test. |
| `rejected/` | Declined / wontfix (for now). Say why. |

Normal flow: `backlog/` (or `urgent/`) → `working/` → `done/`. A ticket may move
to `blocked/` or `rejected/` from anywhere. Re-organize the folder set later if
it stops fitting.

## Filename convention

`<type>-<slug>.md`, lowercase kebab. The name does **not** change when the file
moves between folders.

- Types: `bug`, `feature`, `test`, `chore`, `docs`, `idea`.
- Filter by type across all states, e.g.:
  - `git ls-files 'docs/progress/*/bug-*'`
  - `ls docs/progress/*/feature-*`

## Ticket shape

```markdown
# Short title

- **Type:** bug | feature | test | chore | docs | idea
- **Status:** <folder>            (redundant with the folder, but handy in diffs)
- **Owner:** <agent/name or —>    (who holds it while in working/)
- **Found / Opened:** <date + context>

## <body: symptom + repro, or motivation + intended surface + acceptance test>

## Log
- <date> — what happened / what changed.
```

When moving to `done/`, append the commit hash and the regression test that
proves it. When moving to `blocked/`/`rejected/`, append the reason.

## Multi-agent use

- **Claim before working:** `git mv` the ticket to `working/` and set `Owner` in
  the same commit. One file per ticket keeps merge conflicts rare.
- Commit each move as its own small change so the board stays legible in history.
- Found something mid-task you won't fix now: drop a `backlog/` (or `urgent/`)
  ticket and keep going.
- It's a **record + state**, not a clean database. Duplicate or stale tickets are
  tolerated — prefer parking (`blocked/`) to losing information.

Docs only — adding/moving tickets does not touch compiler source, so it skips
the self-host gate. There is no separate index; written status stays in
`../project-state.md` / `../todo.md` as before.
