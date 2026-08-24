# Progress tracker

One unified, file-based board of **tickets** — bugs, features, tests, chores.
One ticket per Markdown file. A ticket is an appendable, editable record: keep a
running `## Log`, never rewrite history away.

Two axes:

- **Status = folder.** Moving the file (`git mv`) is the only state change.
- **Type = filename prefix.** So a single folder of mixed work stays filterable.
  Work-tag prefixes compose with it: `compat-<lang>-*` marks reference-
  compatibility work (FPC/Delphi parity for Pascal, gcc/ISO C for C, ...) —
  see the compat section in `devdocs/dev/parallel-tracks.md`.

This replaces the older split `devdocs/bugs/` and `devdocs/features/` folders.

## Status folders

| Folder | Meaning |
| --- | --- |
| `backlog_new/` | **Where every NEW ticket goes, from 2026-08-24 on.** Ranked exactly like `backlog/`. |
| `backlog/` | Captured before 2026-08-24. Rank is derived. Still worked, no longer filed into. |
| `urgent/` | Human override — do regardless; always sorts to the top. Keep to ~3. |
| `working/` | Claimed and in progress. Set `Owner` so agents don't collide. |
| `unfinished/` | Work halted with the ticket incomplete (parked). Track A/C here is CRITICAL — `check` flags it. |
| `blocked/` | Needs a user decision, external input, or can't-reproduce. Say why. |
| `rainy-day/` | Someday/maybe — real but not now, kept out of the ready queue. |
| `done-followup/` | Done, but spawned a follow-up worth tracking. |
| `done/` | Completed/fixed. Note the commit and the regression test. |
| `rejected/` | Declined / wontfix (for now). Say why. |

Normal flow: `backlog_new/` (or `urgent/`) → `working/` → `done/`. A ticket may
move to `unfinished/`, `blocked/`, `rainy-day/`, or `rejected/` from anywhere.
Re-organize the folder set later if it stops fitting.

### Why `backlog_new/` exists (user, 2026-08-24)

> *"any new bug tickets, important or not, go into `backlog_new`. Instead of
> sorting out, we are going to filter on date — reasoning being, our tickets go
> from gross compiler issues to nitpicking details, and we have a hard time
> sorting them out since they are all called 'bug'. So from here on, any new
> tickets filed are fair game, just they go into `backlog_new`."*

**Filing is free; the sort is by DATE.** `backlog/` grew to where the cost of a
ticket was the cost of *placing* it — is this urgent, is it really a bug, what
prio — and that friction was paid on every finding, including the cheap ones
that are expensive to rediscover. The new folder removes it: **file it, don't
triage it.** "What has come in recently" is then answerable by listing one
folder, which is exactly what `backlog/` could no longer answer.

It is **ranked** (`ready`/`next` scan it alongside `backlog/` and `urgent/`), so
new findings still reach the queue — the split is a filing convenience, not a
parking lot. Contrast `float/` and `experimental/`, which are loaded but
deliberately unranked. `urgent/` is unchanged and still means act-first.

## Filename convention

`<type>-<slug>.md`, lowercase kebab. The name does **not** change when the file
moves between folders.

- Types: `bug`, `feature`, `test`, `chore`, `docs`, `idea`.
- Filter by type across all states, e.g.:
  - `git ls-files 'devdocs/progress/*/bug-*'`
  - `ls devdocs/progress/*/feature-*`

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
prio: 60                          # 0-100 human rating; omit = 50
owner: <agent/name>
blocked-by: [slug, slug]
---

# <slug or title>

## <body, log — same as above>
```

`prio:` is the one human priority knob (see "Priority" below). Rate goals; a
blocker inherits the priority of what it unblocks, so most tickets can stay at
the default 50. It also works as a `**Prio:** 60` bullet, but frontmatter is
preferred for structured fields.

When moving to `done/`, append the commit hash and the regression test that
proves it. When moving to `blocked/`/`rejected/`, append the reason.

## Priority = one human rating (0-100) + dependency propagation

One knob a human sets, everything else derived. No P1/P2 labels, no hand-ranked
global total order (that goes stale and makes agents collide).

- **`prio:` (0-100)** in the ticket's YAML frontmatter — the human's rating.
  Unset = **50**. You only need to rate the things you care about — typically
  the *goals* (a milestone, a feature you want). Blockers inherit; see below.
- **`blocked-by:`** — slugs that must reach `done/` before this is workable.
- **`Unblocks:`** — the inverse edge, for humans; the script derives it from
  everyone's `blocked-by`.

From the rating + the edges, a stable queue falls out:

- **Effective priority = propagation.** A ticket's effective priority is the max
  of its own `prio` and the effective priority of everything it unblocks
  (transitively). So a low-rated bug that blocks a 90-rated feature ranks ~90 —
  it's in the way, so it rises automatically. **Rate the goal; the chain
  follows.** The board shows `own→effective` when they differ.
- **Ready** = a backlog/urgent ticket whose `blocked-by` slugs are all in
  `done/` (or none). Only ready tickets are pullable. The ready list is **sorted
  by effective priority** — highest first.
- **Leverage** = how many tickets name this one in `blocked-by` (a tiebreaker
  after priority).

Keep the edges honest: when you notice "X must land before Y", add `blocked-by`
to Y. Landing X then makes Y ready automatically — no re-ranking.

`urgent/` is the **human override on top of the graph**: a WIP-limited (~3)
"do these regardless," always sorted to the top. For a swarm, still prefer
**locality** — grab tickets in the cluster you're already in (`*managed*`,
`*c-header*`) over the globally highest one.

### Self-serve loop (do tickets at will)

```
tools/progress.sh next --track C   # the single top ticket to grab (+ why)
tools/progress.sh ready --track C  # the whole ranked queue for your track
tools/progress.sh claim <slug> <your-agent-id>   # -> working/, sets Owner
# ... do the work; land only green (your lane's gate) ...
tools/progress.sh resolve <slug>                 # -> done/, logs the commit
tools/progress.sh board-md          # regen BOARD.md/.html; commit with the move
tools/sync.sh                       # push, then record the sha it LANDED as
```

`resolve` takes an optional sha, and you normally omit it: it writes
`PENDING-COMMIT` and `sync.sh` replaces that with the sha the resolve commit
landed as. The sha you could name at resolve time is the pre-rebase one, and
`sync.sh` rebases — on this fleet the watcher publishes tstate every few
minutes, so the cited commit is rewritten away before anyone else can look it
up (`bug-t-resolve-cites-a-sha-the-rebase-then-rewrites`). Pass an explicit sha
only for a commit that already landed. `check --strict` reports both leftovers
(`WARN-PENDING-COMMIT`) and citations absent from origin/master
(`WARN-DEAD-COMMIT`).

Commit the ticket move **together with the fix**: the sha `sync.sh` fills in is
the commit that introduced the placeholder, so a move committed on its own
cites the move rather than the work.

`next` picks the top of the ranked ready queue for the track and prints why it
won (effective priority, what it inherits, what it unblocks). An agent — or
several across tracks — can loop `next → claim → do → resolve` with no human
dispatch. **origin/master is the source of truth**: `git pull --rebase` before
you push, push when your gate is green. Your "working folder" is your set of
Owner-tagged tickets in `working/` — no git worktrees (retired); everyone edits
`master`, the ticket lock + file-ownership rules keep agents off each other's
files. Know your track's gate and its branch/push/pin rules (see
`../dev/parallel-tracks.md`): **push** when green, **pin** only on Track A after
`make stabilize` when a downstream track needs the new binary, **branch** ≈
never.

### Auto-rating

`tools/progress.sh autorate` suggests a `prio:` for every open ticket from
signals already in it — type (bug > feature > idea), any prose priority word
(HIGH/critical/low…), correctness/severity keywords (miscompile, silent-wrong,
SIGSEGV, hang…), and leverage (how many it unblocks). Dry-run by default (prints
`slug  suggested   (reasons)`); `--write` applies it. Deterministic and
dependency-free, so the board stays reproducible.

Writes are tagged `prio: N  # auto`. autorate **never overwrites a human
`prio:`** (a bare line with no `# auto`) — hand-rate the few you care about, let
autorate fill the rest, and re-run `autorate --write` anytime to refresh the
auto ones as tickets change. This is the daily path for a 100+ ticket backlog.

> An LLM can override the rating too: read a ticket, decide a better 0-100, and
> write a bare `prio: N` (no `# auto`) — that pins it as human-set and autorate
> leaves it alone. Use this for judgment the keyword heuristic can't make (e.g. a
> low-severity bug that quietly blocks a strategic goal).

Validate the board: `tools/progress.sh check` (dangling `blocked-by` slugs,
dependency cycles, working/ without Owner, stale `BOARD.md`). Hygiene items like
done tickets without commit notes are warnings by default; `--strict` shows
detail and fails. Render the grid: `tools/progress.sh board-md` → `BOARD.md`
(a **committed** kanban snapshot; deterministic, no timestamp, diffs cleanly) +
`BOARD.html`. Regenerate after any board change — `check` fails on a stale
`BOARD.md`.

`BOARD-brief.md` is the **agent-facing** cut, generated by the same run: queue
head, live locks, blocked/unfinished, ~3KB. `BOARD.md` stays the human kanban.
Both are staleness-checked.

`done/` is **not** enumerated in `BOARD.md`; it gets a count and a pointer to
`BOARD-done.md`, generated alongside and guarded by the same staleness check.
The reason is orientation cost: the done table was 190KB of a 260KB board, so
every agent reading the board to find out what to do paid ~47k tokens for a list
of things nobody can act on. The record is unchanged and still in git — grep
`BOARD-done.md` or `done/` directly. Add a status to `ARCHIVED_STATUSES` in
`tools/progress.py` if another one grows the same way.

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
