---
summary: "In a watcher clone the working tree is a snapshot of the sha under test, not current state. Four separate bugs in one day came from reading it."
type: task
track: T
prio: 65
---

# The watcher's working tree is NOT current state — read `origin/master`

- **Type:** task (Track T — a rule that keeps being rediscovered the hard way)
- **Opened:** 2026-08-02, after the same mistake produced four distinct bugs in
  a single day, two of them in shipped tools.

## The rule

**The watcher clone is DETACHED at the sha under test for most of every cycle.**
Its working tree is therefore a point-in-time snapshot of an *older* commit:

- newer `tstate/reports/*.md` **do not exist there yet**
- `xeon.json` shows that sha's verdicts, not today's
- file **mtimes** are rewritten by every checkout

Measured 2026-08-02, minutes apart, same clone:

| | newest report | failing jobs |
|---|---|---|
| worktree | `210523Z-74a9251` | **1** |
| `origin/master` | `212028Z-4d61f85` | **0** |

So: **anything reading tstate, report files, or mtimes from a checkout is
reading history.** `origin/master` (via `git show` / `git ls-tree`) is the only
truthful source, and it needs no network — the ref is already fetched.

## The four bugs, all the same shape

1. **`make` trusted mtime** to decide `compiler/pascal26` was current. A
   `seed-from-stable` copy is newer than the sources, so make said "up to date"
   and the entire 1098-job matrix silently tested the *pinned* binary
   ([[task-t-seed-from-stable-defeats-rebuild]]).
2. **`twatch --status` read tstate from the worktree** while walking history
   from `origin/master` — fresh history against stale verdicts reported a
   healthy watcher as DOWN, to Track A
   ([[bug-t-status-reads-worktree-tstate-false-down]], fixed `c665a27ed`).
3. **`--follow` matched an exact sha**, but the watcher tests HEAD and skips
   what a burst pushed in between, so it hung forever for its primary user —
   the agent that just pushed (fixed `758b5b62c`).
4. **The health observer** picked the newest report by mtime, then (after a
   partial fix) by name *from the worktree*, and gated on a failing count *from
   the worktree*. Two independent guards, one shared stale input, so they agreed
   and alerted on an already-fixed red — twice.

Note 4 reproduced 2 a few hours after 2 was fixed, in a different tool. Knowing
the rule was not enough; nothing enforced it.

## What would actually stop the fifth

A one-line helper each tool reuses, rather than each rediscovering it:

```python
states_at(repo, "origin/master")     # already exists in twatch.py — use it
```

`twatch.py` grew `states_at()` for exactly this and it is not used anywhere
else. Candidates to route through it: `trackt.py`'s tstate readers, the
dashboard generator, anything under `tools/` that opens a path beneath
`devdocs/progress/tstate/`.

A cheap guard with real teeth: make reading `tstate/**` by filesystem path from
inside a clone that may be detached **fail loudly in review** — a grep in the T
gate would do, since the correct call is always available.

## Not a bug in the watcher

Detaching is correct and deliberate: `twatch` checks out arbitrary shas to test
them, which is why it demands its own clone and refuses a dirty one. The defect
is only in *readers* that assume the tree reflects now.
