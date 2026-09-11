---
track: T
prio: 45
type: bug
status: done
blocked-by: []
owner: claude@borg
summary: "`trackt status`'s code-staleness check hashed the clone's WORKTREE twatch.py, which during a gate is the file at the sha under test — so it reported a current daemon as STALE, and would report a genuinely stale one as current. Fifth instance of 'a watcher clone's worktree is HISTORY'."
---

# The staleness check compared the daemon against the sha under test

- **Type:** bug (Track T — `tools/trackt.py`, `tools/twatch.py`)
- **Found:** 2026-09-11 on borg, while enrolling it as the watcher host.

## The defect

`trackt status` warns when the running daemon predates a landed twatch fix —
added after 2026-08-26, when three landed fixes were absent from the publishing
daemon while every status line said `RUNNING`. It compared:

```py
live_fp = twatch.code_fingerprint(os.path.join(clone, "tools/twatch.py"))
```

That is the file **on disk**, and a watcher clone is detached at the sha under
test for most of every cycle. So the check answered *"is this daemon running the
code of the commit it happens to be testing?"* — which nobody asks.

Measured here:

```
code   : STALE — this daemon is running twatch.py 1d5c476a6328
         while the clone has 17bbd9d15049.
```

| fingerprint | what it actually was |
| --- | --- |
| `1d5c476a6328` | `origin/master:tools/twatch.py` — the daemon was exactly current |
| `17bbd9d15049` | `51901941ef5d:tools/twatch.py` — the pin under verification |

The restart it asked for aborted a running fuzz slice (`twatch: stopping — fuzz
slice discarded`) to replace the code with itself.

## The half that is worse than a false alarm

The same comparison is wrong in the other direction, and there it goes SILENT.
Land a twatch fix while a gate runs on an older sha: the daemon holds the old
code, the worktree holds the old code, they match, and status says nothing. The
check is suppressed at exactly the moment it exists for.

This is the shape `devdocs/dev/track-t.md` already names one level down — the
`NEAR BUDGET` warning that "fires only on a `pass`", an instrument that reports
only in the state where it is not yet needed.

## Why the reasoning that produced it looked right

`code_fingerprint`'s own docstring argues the case:

> A content hash rather than a git sha on purpose: the question is "is the
> process running the code that is on disk", which is independent of whether the
> clone is on a branch, detached at a sha under test, or mid-rebase.

Every clause is true. "The code that is on disk" is simply not the subject: what
matters is the code a restart would LOAD, which lives on `origin/master` and
only coincides with the worktree when the clone is on its branch. A true fact
standing in for the deciding one — the same pattern as `pgrep` matching the
waiter's own command line, and it is why re-reading the condition confirms it.

**Fifth instance of the rule** in `track-t.md`: *a watcher clone's worktree is
HISTORY, not current state*. The four recorded there are all readers of
`tstate/`; this one reads `tools/`. `tools/tstate_reader_devtest.py` enforces
the rule for readers that join a clone path with the tstate directory, so it
could not have seen this — the guard is scoped to the directory rather than to
the mistake.

## Fix

`twatch.deployed_code_fingerprint(repo)` — the fingerprint of the twatch.py a
restart would load: `origin/<branch>:tools/twatch.py` when the clone is
detached, the worktree file when it is on a branch (where the two are the same
thing). `trackt status` calls it instead of hashing the path.

`tools/twatch_codefp_devtest.py` guards both directions on a synthetic
two-commit fixture, including a live-fixture row: if its two versions ever
became identical every other row would pass while testing nothing.

## Log
- 2026-09-11 — fixed in the same commit as this ticket. Verified on a scratch
  clone detached 400 commits back: worktree `3fc2b7d4b6d5`, deployed
  `1d5c476a6328` = `origin/master`.

## Follow-up worth considering, NOT filed as done
`tstate_reader_devtest.py`'s `ALLOWED` list is keyed on readers of the tstate
directory. The rule it enforces is about the worktree, not about that
subdirectory, and this bug lived in the gap. Whether the guard should widen to
"any reader that joins a clone path with a repo-relative path" is a real design
question with a real cost — it would sweep in every legitimate build path — so
it is named here rather than answered.
