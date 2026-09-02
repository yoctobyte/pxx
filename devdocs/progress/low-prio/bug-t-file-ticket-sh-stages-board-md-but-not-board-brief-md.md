---
track: T
prio: 40
type: bug
status: low-prio
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "`tools/file-ticket.sh` runs `tools/progress.sh board-md`, which regenerates BOTH devdocs/progress/BOARD.md and BOARD-brief.md, then `git add`s only BOARD.md. The unstaged BOARD-brief.md makes the following `git pull --rebase` abort with 'cannot pull with rebase: You have unstaged changes', so the script dies after committing, never pushes, and leaves a worktree behind that it explicitly does not clean up. Reproduced twice; every ticket filed through the tool hits it whenever the board regeneration touches the brief."
---

# `file-ticket.sh` stages `BOARD.md` but not `BOARD-brief.md`, then cannot rebase

## What happens

```
$ tools/file-ticket.sh devdocs/progress/backlog-core/some-ticket.md
Preparing worktree (detached HEAD 6d5672c9a)
...
error: cannot pull with rebase: You have unstaged changes.
error: Please commit or stash them.
file-ticket: rebase conflict; resolve manually in /tmp/tmp.XXXXXXXX (NOT auto-cleaned)
```

The message says "rebase conflict". There is no conflict — the rebase never
started.

## Cause

The board-refresh block:

```sh
if [ -x tools/progress.sh ]; then
  tools/progress.sh board-md >/dev/null 2>&1 || true
  git add devdocs/progress/BOARD.md >/dev/null 2>&1 || true
fi
git commit -q -m "docs(tickets): sync ticket(s) to master ..."
git pull --rebase -q "$REMOTE" "$BRANCH" || { ...die... }
```

`tools/progress.sh board-md` regenerates `BOARD.md` **and**
`BOARD-brief.md`. Only the first is staged, so the commit lands with a
half-refreshed board and `BOARD-brief.md` is left dirty in the worktree.
`git pull --rebase` refuses to run with unstaged changes, and the script exits 2
on a path whose message blames a conflict.

Confirmed in the failing worktree:

```
$ git status --porcelain
 M devdocs/progress/BOARD-brief.md
$ git show --stat HEAD
 devdocs/progress/BOARD.md   | 12 +-
 <the tickets>
$ git diff --stat devdocs/progress/BOARD-brief.md
 devdocs/progress/BOARD-brief.md | 8 ++++----
```

## Consequences

1. **The tool never pushes.** Tickets stay unlanded, which defeats its entire
   purpose — the header says tickets live on master "so EVERY track sees it".
2. **It leaves the worktree behind on purpose** (`trap - EXIT`), so repeated
   failures accumulate `/tmp/tmp.*` worktrees plus stale `git worktree` entries.
3. **The two board files end up inconsistent** in the commit it did make: they
   are generated from the same source, and only one was refreshed.
4. **The error message misdirects.** "rebase conflict; resolve manually" sends
   the reader looking for a conflict that does not exist.

## Fix

Stage whatever the generator touched, not a hard-coded filename:

```sh
tools/progress.sh board-md >/dev/null 2>&1 || true
git add -A devdocs/progress/BOARD.md devdocs/progress/BOARD-brief.md 2>/dev/null || true
```

or, more robustly, `git add -A devdocs/progress/` after the refresh — the
worktree is throwaway and nothing else should be dirty in it.

Worth separating the two failure paths while there: a rebase that cannot START
(dirty tree) is a different problem from one that conflicts, and only the second
justifies leaving the worktree for a human.

## Workaround until fixed

In the leftover worktree: `git add devdocs/progress/BOARD-brief.md &&
git commit --amend --no-edit && git pull --rebase origin master &&
git push origin HEAD:master`, then `git worktree remove --force` it.

Found while filing three tickets on 2026-09-01; hit it on both invocations.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
