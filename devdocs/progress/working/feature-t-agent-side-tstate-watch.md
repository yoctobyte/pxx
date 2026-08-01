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
