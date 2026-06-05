# Progress tracker — design notes

Design and rationale for the `docs/progress/` board. The terse operating rules
live in `AGENTS.md` (loads every session) and the file-format spec lives in
`docs/progress/README.md`. **This file is the "why".** Other agents are invited
to review and push back on it.

Status: adopted 2026-06-06. Small board (~25 tickets), mostly single-agent today,
built to scale to many agents / 100+ tickets without re-architecture.

## Goal

A bug/feature/work tracker that is:

- **Git-native** — history, diffs, blame, offline, no external service or DB.
- **Agent-parseable** — plain Markdown + filesystem layout, no API.
- **Multi-agent safe** — several agents can work in parallel with rare conflicts.
- **A record *and* a state** — keep the full story of an item *and* answer
  "what's its status right now" without reading git log.

## The four axes

Everything an item needs is expressed without a database:

| Axis | Encoded as | Filter |
| --- | --- | --- |
| **Status** | which folder | `ls docs/progress/<folder>` |
| **Type** | filename prefix (`bug-`, `feature-`, `test-`, `chore-`, `docs-`, `idea-`) | `git ls-files 'docs/progress/*/bug-*'` |
| **Topic** | slug substring | `git ls-files 'docs/progress/*/*managed*'` |
| **Priority** | dependency edges (derived) | `tools/progress.sh` |

One ticket = one file. Moving the file (`git mv`) is the only state change.

## Why not the obvious alternatives

- **Why not a label/field for status?** A folder makes status a property of *where
  the file is*, so a plain `ls` answers it and a move is a one-line diff. No field
  to keep in sync with reality.
- **Why type in the filename, not a folder?** Status and type are independent
  axes. Folders model one axis cleanly; cramming both (`bugs/working/…`) doubles
  the tree and makes a status move also a type decision. Filename prefix keeps
  type filterable across all states.
- **Why no P1/P2 priority labels?** A hand-assigned rank is a *global total order*.
  This project has dependency chains (managed-string needs by-ref param store +
  exception cleanup first; CPU targets are staged), locality (an agent in the
  allocator should grab allocator work), and multiple agents (a global "P1" makes
  them all grab the same item). A fixed rank goes stale the moment a dependency
  lands and actively causes collisions. So priority is **derived**, never stored.

## Priority by dependency (the core idea)

Two optional ticket fields encode edges:

- `Blocked-by:` — slugs that must reach `done/` before this is workable.
- `Unblocks:` — the inverse, for human readability (the script derives the real
  graph from everyone's `Blocked-by`).

From those, two quantities are computed and never go stale:

- **Ready** — a `backlog/`/`urgent/` ticket whose `Blocked-by` slugs are all in
  `done/` (or it has none). Only ready tickets are pullable.
- **Leverage** — how many tickets name this one in their `Blocked-by`. High
  leverage + ready = the natural "do first": it frees the most downstream work.

Landing a ticket (moving it to `done/`) automatically recomputes readiness for
everything it blocked — no re-ranking pass. Example today:
`feature-unified-heap-allocator` has leverage 3 and is ready, so it surfaces as
the do-first without anyone labeling it.

Discipline this needs: when you notice "X must land before Y", add `Blocked-by:
X` to Y. That single edit is the whole maintenance cost.

## Multi-agent semantics

- **Claim before working:** `git mv` the ticket to `working/` and set `Owner` in
  the same commit. The move is visible to every other agent immediately on pull.
- **One file per ticket** → edits by different agents touch different files →
  merge conflicts are rare and, when they happen, local to one ticket.
- **Pull by locality, not global rank.** Prefer ready tickets in the topic
  cluster you are already editing (`*managed*`, `*c-header*`) over the globally
  highest-leverage one. Locality beats priority for avoiding collisions and
  context-switch cost.
- **`urgent/` is the human override.** A WIP-limited (~3) "do these regardless of
  the graph." Scarcity forces a real choice; if everything is urgent, nothing is.

## The script

`tools/progress.sh [ready|leverage|board|all]` (default `all`) prints the board
summary, leverage ranking, and the ready queue. It is a convenience over the
same data a human or agent can `grep`; the Markdown is the source of truth, the
script is disposable.

## Tradeoffs and known limits

- **Edges need discipline.** A missing `Blocked-by` means a ticket looks ready
  when it isn't. Mitigated because the cost of adding one edge is trivial and
  any agent can add it when noticed.
- **Slug typos fail silent-ish.** A `Blocked-by:` slug that matches no real
  ticket can never be in `done/`, so the ticket stays "not ready" forever.
  Treat an unexpectedly-never-ready ticket as a possible typo. (A future script
  check could flag dangling slugs.)
- **No cycle detection.** Nothing stops `A blocked-by B` + `B blocked-by A`. The
  script would just show neither as ready. Keep the graph a DAG by hand.
- **No transitive readiness display.** "Ready" only checks direct blockers being
  in `done/`; it does not rank by depth of the chain behind a ticket. Leverage is
  a one-hop count, not a full reachability weight. Good enough; revisit if the
  board grows large.
- **Duplicate / stale tickets tolerated by design.** This is a record + state,
  not a normalized DB. Prefer parking (`blocked/`/`triage` via `blocked/`) to
  deleting information.
- **README template is excluded** from the script's scans by name so its
  placeholder `Blocked-by:` lines don't pollute leverage counts.

## Possible extensions (not built)

- A `progress.sh check` that flags dangling `Blocked-by` slugs and cycles.
- A generated `BOARD.md` snapshot for humans (kept out for now — the filesystem
  *is* the index; a generated file would just drift).
- Promote `Owner` to include a timestamp for stale-claim detection.

## For reviewing agents

If you change this system, update `docs/progress/README.md` (format),
`AGENTS.md` (rules), and this file (rationale) together, and keep
`tools/progress.sh` in step. Disagreements welcome — leave them as an `idea-`
ticket on the board itself.
