---
summary: "twatch --status reads tstate from the WORKTREE but walks history from origin/master, so a detached or unpulled checkout reports Track T DOWN while it is healthy"
type: bug
track: T
prio: 80
---

# `--status` mixes two sources and reports a healthy watcher as DOWN

- **Type:** bug (Track T — `tools/twatch.py`, the liveness check every dev track gates on)
- **Found:** 2026-08-01, when **Track A reported "Track T is down"** while the
  watcher was healthy and fully current.

## What Track A saw

```
tstate: DOWN — b78988fe8977 untested for 200 min (> 45 min grace); run your own full gate
```

## What was actually true

`b78988fe8977` (the newest *code* commit, 13:29) had been tested and published
**four times**:

| | |
|---|---|
| native | 13:32 GREEN |
| full | 13:35 GREEN |
| opt | 13:40 GREEN |
| bench | 13:49 ok |

Everything after it on master is xeon's own tstate. The daemon was idle because
the repo had been quiet for three hours — correctly idle, head tested, nothing
to do. Track T was never down.

## Cause — two sources, one of them stale

`status()` takes its two inputs from **different places**:

- **the commit walk** already prefers `origin/master`, deliberately: *"a dev
  checkout drifts behind it constantly… 2026-07-20 a checkout 226 commits behind
  reported UP while the daemon had been stopped for hours"*
- **the tested-set** comes from the **worktree**: `tdir = tdir or
  os.path.join(repo, TSTATE_REL)` (twatch.py:1522), and `--status` never passes
  `tdir`, so it always takes the worktree.

Fresh history + stale verdicts = commits that look untested. The mismatch *is*
the bug.

It bites in both directions of the fleet:

- **In the watcher's own clone** — the worktree is **detached at the sha under
  test for most of every cycle**, so its tstate files lag whatever the daemon
  has already pushed. Measured here: `--status` read `last = fd13045eb7c7
  (11:25:45Z)` while origin already had `b78988fe8977 (11:40:40Z)`. The window
  is transient, which is why it reads as intermittent flakiness.
- **In a dev checkout** — the tstate files are only as fresh as the last `git
  pull`, which on a working box can be hours.

The function's own docstring anticipates exactly this and provides the `tdir`
parameter to fix it — *"the caller can point this at data read from
`origin/master` instead, which is what the daemon actually publishes to"* — and
then the `--status` CLI never uses it.

`tools/trackt.py` already does the right thing (`git show origin/master:…`,
trackt.py:219), which is why `trackt status` was accurate throughout while
`twatch.py --status` was not. The protocol tells every dev track to run the
**wrong one of the two**.

## Why this one matters more than its size

Since the operating model made xeon's `fast_tier` the project gate, `--status`
is the single check standing between "push on a 15 s quick tier" and "run your
own full gate". A false DOWN sends every dev track back to a 10-minute local
matrix for no reason — the exact cost Track T exists to remove. And it erodes
trust in the one signal that is supposed to be authoritative: this is the third
time it has fired wrongly.

## Fix

Read **both** inputs from the same ref. Load the per-host `*.json` from
`origin/master` via `git show`, fall back to the worktree only when the ref is
unavailable (no remote, fresh clone):

```python
def states_at(repo, ref):
    names = sh(["git", "ls-tree", "--name-only", "%s:%s" % (ref, TSTATE_REL)],
               cwd=repo, check=False).split()
    ...  # json.loads(git show ref:TSTATE_REL/n) for each *.json
```

Keep the no-network contract: read whatever `origin/master` the checkout already
has, do not fetch. A checkout that is behind then reports on a consistently old view
rather than an incoherent mixed one, which is the honest answer.

Worth adding while in here: when the verdict is DOWN, print the newest tested
sha per host and the age of the *oldest untested* commit, so the reader can see
at a glance whether the watcher is dead or the checkout is stale.

---

## FIXED — `c665a27ed` (claude@xeon, 2026-08-01)

`states_at(repo, ref)` reads the per-host tstate json out of the ref with git
plumbing, and `status()` now uses it so **both inputs come from the same ref**.
Falls back to the worktree when the ref carries no tstate (fresh clone, no
remote). No network and no fetch — same contract as before.

### Verified on the exact failing condition

A clone detached 25 commits back, worktree tstate stale, origin current:

| | reads | verdict |
|---|---|---|
| before | worktree `ac372419dbea` (10:27:59Z) | **DOWN** — "b78988fe8977 untested for 206 min" |
| after | origin `b78988fe8977` (11:40:40Z) | **UP** — "commits through b78988fe8977 tested" |

Fallback separately confirmed: a clone with the remote removed still reports UP
off its worktree.

### A note on how this was nearly mis-tested

The first attempt "failed" — the fix appeared not to work. The cause was the
test, not the fix: `git checkout --detach` also reverted `tools/twatch.py` to
the 25-commits-ago version, so the old code was being measured. Worth
remembering when reproducing anything in a detached watcher clone: **you get
that sha's tooling too**, which is the same trap as testing against a stale
compiler binary.

### Deliberately not changed

The grace-window semantics are untouched. `--status` still means "every commit
older than the grace window was tested by some host", and it will still report
DOWN if the watcher genuinely stops. What is fixed is only the incoherent
mixing of a fresh commit walk with stale verdicts.

The DOWN message could still say more — newest tested sha per host, age of the
oldest untested commit — so a reader can tell "watcher dead" from "checkout
stale" at a glance. Left for a follow-up; it is presentation, not correctness.

## Log
- 2026-08-01 — resolved, commit c665a27ed.
