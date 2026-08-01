---
summary: "An agent session has no way to hear Track T's verdict on a sha it just pushed; a small poll tool would deliver reds while the context that caused them is still warm"
type: feature
track: T
prio: 65
---

# A tool that tells the pushing agent when T reds one of ITS shas

- **Type:** feature (Track T tooling, closes the loop) — **Track T**
- **Opened:** 2026-08-01.

## Why

Dev tracks are moving to: build (12s) → check the repro → push, with breadth
offloaded to T. That trade only pays if the agent **hears back while its context
is still warm**. Today it does not: T publishes to `tstate/` in its own clone and
pushes, and nothing tells the session that pushed the sha. The finding lands in a
session that has already ended, so the next agent pays full re-investigation
cost — which is most of what the offload was supposed to save.

This is the missing half of "confirm native, offload the matrix". The offload
exists; the return path does not.

## Asked for

A small poller — `tools/twatch.py --follow <sha>...`, or a `trackt watch`
subcommand — that:

1. `git fetch` on an interval (no network beyond origin; it reads `tstate/`,
   same as `--status`).
2. Reports when a verdict lands for any sha in a given set — defaulting to
   **"shas authored by me that origin/master contains and tstate has not yet
   judged"**, so an agent can start it once and forget it.
3. Exits non-zero / prints loudly on RED, quietly on GREEN, and says
   "still unjudged" rather than implying success when nothing has arrived —
   silence must not read as green (the same trap `--status` already documents).

It should be safe to run inside a dev checkout: read-only with respect to
everything but its own output, and it must not `git pull --rebase` the agent's
tree out from under them.

## Notes

- Pairs with [[feature-t-publish-selfhost-red-immediately]]: fast publication is
  worth little without something listening, and a listener is worth little if
  publication waits for a whole tier.
- `--status` already reads `tstate/` versus git history and is the obvious code
  to build on. Note the trap recorded on `bug-t-status-reads-worktree-tstate-false-down`
  and in eeae1e4a3's message: **it reads the LOCAL tstate directory**, so
  without a fetch first it reports the staleness of your own checkout rather
  than the watcher's. A follow mode must fetch every poll or it will
  confidently report nothing forever.

## Gate

Push a sha that T will red; the follow tool surfaces it on the next poll, names
the failing job and the sha, and is distinguishable from "no verdict yet".

---

## DONE — `e5731e25f` (claude@xeon, 2026-08-01)

```
tools/twatch.py --follow [SHA...] [--poll N] [--once]
```

Defaults to unjudged commits on `origin/<branch>`, fetches every poll, reports
each verdict as it lands, and names anything still unjudged **explicitly as NOT
a pass**.

Exit codes so a caller need not parse text:

| code | meaning |
|---|---|
| 0 | every watched sha judged GREEN |
| 1 | a RED was seen (outranks pending — it is the actionable one) |
| 2 | still unjudged |

### One deviation from the ask

> defaulting to **"shas authored by me** that origin/master contains…"

Author-filtering is **not** implemented, deliberately. Every agent in this fleet
commits as the same git identity (`yoctobyte`), so `--author` would select other
agents' work as readily as mine and mean nothing. The default is "unjudged on
origin/<branch>", which is the useful set in practice; pass explicit shas when
you want exactly yours.

### The trap you flagged, and one more underneath it

You warned that `--status` reads the local tstate and would "confidently report
nothing forever" without a fetch. That is now doubly handled: `--status` reads
tstate from the `origin/master` **ref** (fixed in `c665a27ed`), and `--follow`
fetches that ref every poll.

The gate then caught a second-order version of the same bug in my own code: the
**default sha set is derived from `origin/<branch>`**, so the fetch has to
precede selection, not merely happen inside the poll loop. With a stale ref the
first version selected the wrong shas; with the ref deleted outright it selected
*nothing* and exited **0**, reporting success — precisely the
silence-reads-as-green failure this tool exists to prevent. Fixed, and verified
by deleting `refs/remotes/origin/master` and confirming `--follow` restores it
and still finds the reds.

### Verified

- exit codes: mixed red+pending → 1, known RED → 1, known GREEN → 0,
  never-judged sha → 2
- read-only: `HEAD` and `git status --porcelain` byte-identical across a run —
  it never pulls, rebases or checks out
- live: surfaced `b9b1ac4d5761 RED (native, xeon)` and listed four shas as still
  unjudged rather than implying they had passed

### Pairing

With [[feature-t-publish-selfhost-red-immediately]] landed, a self-host break now
publishes in ~22 s and `--follow` surfaces it on the next poll — the two halves
the tickets said were worth little apart.

## Log
- 2026-08-01 — resolved, commit e5731e25f.
