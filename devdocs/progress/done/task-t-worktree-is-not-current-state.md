---
summary: "In a watcher clone the working tree is a snapshot of the sha under test, not current state. Four separate bugs in one day came from reading it."
type: task
track: T
prio: 65
status: done
owner: claude@xeon
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

## Log
- 2026-08-04 (`claude@xeon`) — done as the ticket specifies: the shared helper
  first, then the guard, because the ticket's own point is that knowing the rule
  did not stop instance #4 from reproducing instance #2.

  **`materialize_tstate(repo, ref)`** joins `states_at()` in `twatch.py`. It
  brings the WHOLE subtree — `reports/`, `bench.tsv`, `conformance.tsv` — via
  one `git archive`, because `states_at` covers only host json and the next
  reader that needed more would have written its own and got it wrong again.
  Returns None when the ref carries no tstate, so a caller falls back to the
  worktree deliberately rather than by accident. `head_detached()` is the
  predicate the whole rule turns on.

  **The dashboard now uses it.** `twatch_web.export_static` read
  `<clone>/devdocs/progress/tstate` directly, so `trackt dashboard` run while
  the daemon was mid-test rendered the tested sha's snapshot as if it were
  current — instance #4's family, in a shipped tool. It now reads the ref when
  HEAD is detached and says which source it used. Verified against the live
  watcher clone while it was detached: *"HEAD is detached (mid-test) —
  rendering from origin/master, not the worktree snapshot"*.

  **`tools/tstate_reader_devtest.py` is the teeth the ticket asked for.** A tool
  that joins a clone path with the tstate directory must route through the
  helpers or be added to `ALLOWED` with a reason. It found three files I had not
  known about, and each got a different verdict rather than a blanket pass:
  `testmgr.py` was a FALSE positive (it discusses tstate at length in comments
  and touches none of it — so the pattern now requires real path construction,
  or the guard becomes noise and gets muted, which is how enforcement dies);
  `uforth_bench.py` is a writer running from a dev checkout; the close-stubs
  devtest joins its own fixture's path.

  Not changed, deliberately: `trackt.runs_files()` tails `runs-*.ndjson` from
  the worktree. That one is correct — the live view wants rows the moment the
  daemon appends them, which is before the publish that would put them on the
  ref. It is in `ALLOWED` with that reason rather than silently exempt.

  The rule itself is now in `devdocs/dev/track-t.md` with the measurement that
  makes it concrete (worktree `210523Z-74a9251`, 1 failing; `origin/master`
  `212028Z-4d61f85`, 0 failing, minutes apart in the same clone).

- 2026-08-04 — resolved, commit PENDING-COMMIT.
