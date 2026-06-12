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

Two equivalent formats — different agents prefer different ones, the tooling
reads both. Frontmatter wins for scalar fields when a file mixes them;
`Blocked-by` slugs are merged from both.

Markdown-bullet style:

```markdown
# Short title

- **Type:** bug | feature | test | chore | docs | idea
- **Status:** <folder>            (redundant with the folder, but handy in diffs)
- **Owner:** <agent/name or —>    (who holds it while in working/)
- **Blocked-by:** <slug, slug>    (omit when nothing blocks it)
- **Unblocks:** <slug, slug>      (omit when it blocks nothing)
- **Found / Opened:** <date + context>

## <body: symptom + repro, or motivation + intended surface + acceptance test>

## Log
- <date> — what happened / what changed.
```

YAML-frontmatter style (`summary` replaces the H1 in BOARD.md; inline
`[a, b]` and block lists both work for `blocked-by`):

```markdown
---
summary: "Short title"
type: bug | feature | test | chore | docs | idea
owner: <agent/name>
blocked-by: [slug, slug]
---

# <slug or title>

## <body, log — same as above>
```

When moving to `done/`, append the commit hash and the regression test that
proves it. When moving to `blocked/`/`rejected/`, append the reason.

## Priority = dependencies, not labels

There are **no P1/P2 labels**. A hand-assigned priority is a global total order;
this project has dependency chains, locality, and several agents — a fixed rank
goes stale and makes agents collide on the same item. Instead, priority is
*derived* from edges that are cheap to keep correct:

- **`Blocked-by:`** — slugs that must reach `done/` before this is workable.
- **`Unblocks:`** — slugs this one frees up (the inverse edge, for humans;
  the script derives it from everyone's `Blocked-by`).

From those two fields, priority falls out and never goes stale:

- **Ready** = a backlog/urgent ticket whose `Blocked-by` slugs are all in `done/`
  (or it has none). Only ready tickets are pullable.
- **Leverage** = how many tickets name this one in their `Blocked-by`. High
  leverage + ready = do it now; it frees the most downstream work.

Keep the edges honest: when you notice "X must land before Y", add `Blocked-by`
to Y. Landing X then makes Y ready automatically — no re-ranking.

`urgent/` is the **human override on top of the graph**: a WIP-limited (keep it
to ~3) "do these regardless." Scarcity forces a real choice. For a swarm, prefer
pulling by **locality** — grab tickets in the topic cluster you're already in
(`*managed*`, `*c-header*`) over the globally "highest" one.

Compute the queue: `tools/progress.sh` (ready list + leverage + board summary).
Validate the board: `tools/progress.sh check` (dangling `Blocked-by` slugs,
dependency cycles, working/ without Owner, done/ without a commit).
Render a human grid: `tools/progress.sh board-md` → `BOARD.md` (a **committed**
kanban snapshot; its git history is the board's progress log). Regenerate it
after any board change — `check` fails on a stale `BOARD.md`. The render is
deterministic (no timestamp) so it diffs cleanly.

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
`../developer/project-state.md` / `../developer/todo.md` as before.
