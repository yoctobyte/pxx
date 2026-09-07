---
track: T
prio: 90
type: bug
status: done
owner: ""
created: 2026-09-07
found-by: frank-seven
tags: [twatch, tstate, deadlock, self-heal, availability]
blocked-by: []
summary: "note_idle_tier_try() writes seven.json AFTER the cycle's tstate self-heal and BEFORE `git checkout --detach`, so the checkout aborts on the file the heal just published. It recurs identically every cycle: heal, re-dirty, abort. Ten consecutive failures, then `giving up`, then eleven systemd restarts each refusing the now-dirty tree, then Result: exit-code and the box is dark. Observed on seven 2026-09-07 17:01-17:06Z; it killed a running full tier. This is the exact deadlock shape publish_tstate_dirt() was written to end, and it defeats it because the write recurs after the heal rather than before it."
---

# The loop, from the log

```
twatch: 1 uncommitted tstate file(s) — ours by definition, publishing rather than pausing on them: seven.json
twatch: 889383578da3..1482f1c28449 is docs/tstate-only — no gate needed
twatch: testing 889383578da3 (full)
twatch: cycle failed (9/10): cmd failed (1): git checkout --quiet --detach 889383578da3
error: Your local changes to the following files would be overwritten by checkout:
	devdocs/progress/tstate/seven.json
Aborting
...
twatch: 10 consecutive failures — giving up
twatch: /home/seven/trackt-watch has uncommitted changes — this looks like a dev checkout, not a dedicated watcher clone. Refusing.
M devdocs/progress/tstate/seven.json      (x11, then systemd start-limit)
```

The whole diff, every cycle, is one bookkeeping field:

```diff
  "last_idle_tier_try": {
-  "date": "2026-09-07T16:59:58Z",
+  "date": "2026-09-07T17:01:04Z",
   "sha": "889383578da30ffa594699a7622870929d90c85f",
   "tier": "full"
```

# Mechanism

`publish_tstate_dirt()` runs at the top of the cycle, finds `seven.json` dirty,
correctly decides it is "ours by definition", and publishes it. The tree is
clean. Then the idle ladder selects the full tier and calls
`note_idle_tier_try()` (`tools/twatch.py:6418`), which does
`save_state(...)` — **dirtying `seven.json` again** — and only then does the
cycle `git checkout --quiet --detach <sha>`, which refuses.

Both halves are individually correct and recently, deliberately added:

* `note_idle_tier_try()` writes **before** the run on purpose. Its docstring is
  explicit: *"an attempt that never lands is exactly the case this has to
  record"* — added 2026-09-06 after the fleet spent an evening unable to tell
  from published state whether a full tier had even been entered.
* `publish_tstate_dirt()` exists precisely so that *"any bare `save_state()`
  from any future path self-heals on the next cycle rather than taking the box
  dark"*, after that deadlock had already happened twice (`last_opt` 2026-07-11,
  `mark_infra()` 2026-08-12, the latter costing 16 hours).

The heal's promise fails here because it is **positional**, not invariant: it
holds for a `save_state()` that happened before the heal ran, and the new call
site writes after it. "Self-heals on the next cycle" assumes the dirt does not
recur at the same point of every cycle. This one does, so each cycle publishes
a commit and then dies at the same line — the loop even generates archive
traffic while making no progress.

# Why this is prio 90 rather than an annoyance

It takes the box **dark**, and it does so silently after `Restart=on-failure`
exhausts its start limit: `Active: failed (Result: exit-code)`, no daemon, no
report, and the last log line is a refusal that reads like operator error
("this looks like a dev checkout"). It killed a live full-tier run on the day
that run became release evidence. Recovery needed a human to notice the box had
gone quiet, revert one timestamp, and `systemctl --user reset-failed`.

Note also that **the standing operator advice is now wrong**: a mid-cycle
`checkout --detach` failure on `seven.json` has been treated as expected and
self-resolving. In this path it never resolves.

# Fix

`88a290623`, taking the first of the three options below. `Clone.checkout()`
catches the refusal and, if `publish_own_writes()` can account for every dirty
path, publishes and retries **once**; a second failure re-raises untouched, so
this turns a wedge into a retry and never into a loop. With no host set
(devtests, one-shot tools) the checkout stays strict and publishes nothing.
Three guards in `tools/devtest_wedge_on_own_writes.py`, including that a dev
edit still refuses the checkout and still survives it.

Options considered, in the order preferred:

1. **Make the checkout tolerant of our own dirt** — chosen. It restores the
   invariant the heal's docstring claims rather than patching one more call
   site, which is the argument that docstring itself makes.
2. Re-run `publish_own_writes()` immediately before the checkout. Narrower, but
   it fixes the position rather than the shape, so the next write after the new
   heal point reopens it.
3. Fixing `note_idle_tier_try()` alone is the *third* option, not the first:
   that would be the fourth call site fixed individually, and the pattern says
   a fifth arrives.

A note kept from writing the guards: two of them passed for the wrong reason at
first. Checking out the sha you are already on never conflicts, whatever is
dirty — git only refuses a checkout that would overwrite a local change — so a
reproduction needs a target whose content for that path actually differs.

Also worth separating: `10 consecutive failures — giving up` followed by
systemd's start limit converts a recoverable condition into a dark box with no
alert. Whatever else changes, the daemon exiting for good should be loud.

## Log
- 2026-09-07 — found on seven after the daemon stopped mid-full-tier; diagnosed
  from the log and `git diff`, recovered by reverting the one-line timestamp and
  `systemctl --user reset-failed`. Filed by frank-seven.
- 2026-09-07 — it recurred exactly as predicted 70 minutes later, killing the
  cycle straight after the GREEN full tier at `2b692bbb71b3` (the first clean
  full run any live host has produced). Recovery without the fix buys one cycle,
  so the fix is the recovery. Closed by `88a290623`.
