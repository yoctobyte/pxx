---
summary: "a full run replaces the whole jobs map, so opt-tier reds re-announce as NEW-RED forever"
type: bug
track: T
prio: 70
---

# A `full` run wipes job statuses the full tier does not cover

- **Type:** bug (Track T watcher state) — filed by `claude@borg` 2026-08-01
- **Found:** watching `optdiff#shard5/6` report **NEW-RED twice** for the same
  never-fixed failure.

## Evidence (from xeon's own run archive)

| time | tier | `full` | verdict | `new_red` |
|---|---|---|---|---|
| 21:33:57Z | opt | False | RED | `['optdiff#shard5/6']` |
| 21:45:48Z | native | False | GREEN | `[]` |
| **21:49:29Z** | **full** | **True** | RED | `[]` |
| 22:00:12Z | opt | False | RED | `['optdiff#shard5/6']` ← again |

The job never went green. It was announced as *newly* red twice.

## Mechanism

`twatch.py`, state persistence:

```python
if full:
    st["jobs"] = now                       # <-- REPLACES the whole map
else:
    st["jobs"] = dict(st["jobs"], **now)   # merges
```

`now` contains only the jobs *that run in this tier*. The `full` tier does not
run `optdiff` — those are generated for tier `opt`
(`TIERS["opt"] = ["test-opt"]` plus `OPT_SHARDS` optdiff jobs). So:

1. opt run records `optdiff#shard5/6: fail` (merged in — correct)
2. **any** full run replaces the map with full-tier jobs only ⇒ every optdiff
   entry is **erased**
3. the next opt run computes
   `prev_jobs.get("optdiff#shard5/6", "pass") == "pass"` ⇒ **NEW-RED**, forever

## Why it matters more than it looks

- **The NEW-RED/STILL-RED distinction is the fleet's alerting primitive.** The
  whole "only alert on change" model — and the report format, and any agent-side
  filter — rests on it. A job that re-announces as new after every full run
  poisons that signal permanently.
- **`open_regressions` cannot hold these.** `reg_open()` consults the merged
  authoritative map, which has just lost the entry, so an opt-tier regression
  never persists in the ledger. `xeon.json` currently shows
  `open_regressions: []` while `optdiff#shard5/6` is red.
- **It re-introduces a class this file already fixed once.** `job_key()` carries
  a long comment about not "manufacturing NEW-RED/FIXED pairs out of nothing"
  (positional renumbering), and `reg_open()` was fixed on 2026-07-20/21 to use a
  *merged* map precisely so a lucky run could not close a cascade. The
  `st["jobs"] = now` replacement is the same bug shape, one level up: a partial
  view overwriting a whole-fleet ledger.

## Fix direction

The replacement is presumably there to garbage-collect jobs that no longer
exist, which merging alone never does. Both goals are satisfiable:

- **merge always**, and prune separately — drop keys that are absent from the
  *union* of currently-known job names (`testmgr --list` per tier), not from
  whatever one tier happened to run; or
- **scope the replacement to coverage** — on a full run replace only the keys
  the full tier actually covers, leaving other tiers' statuses intact.

Either way the invariant to hold is: **a tier may only overwrite statuses for
jobs it actually ran.**

## Verification

Reproduce cheaply without long runs: take a state file with an `optdiff` entry
at `fail`, apply a full-tier report that contains no optdiff jobs, and assert
the entry survives. Then the sequence above stops producing a second NEW-RED.

## Notes

Filed by Track T face 2; this *is* T's own tooling, so it is xeon's to fix.
Related but distinct: the auto-filed stub for this same red said "last good
unknown, 0 commits in range" when the previous green opt run was one entry back
in `runs-xeon.ndjson` — see [[regression-optdiff-shard5-6]].

---

## FIXED — `5f1596bde`, deployed (claude@xeon, 2026-08-01)

`covered_tiers()` encodes that the regression tiers nest
(`quick < native < limited < full`) while `opt` is **disjoint**, plus a
`job_tier` map recording which tier last spoke for each key. A run may now only
evict jobs it was capable of running; keys owned by an uncovered tier are
carried forward.

Verified against the observed `opt/full/opt/full/opt` sequence, with the live
daemon's own unpatched copy as the negative control:

| | NEW-RED on runs |
|---|---|
| before | 1, 3, 5 — the same never-fixed red, re-announced every cycle |
| after | 1 only — the genuine first sighting |

Separately confirmed a job genuinely removed from the full tier is still
evicted, so the eviction the replace existed for still happens.

Deployed: the daemon was restarted onto it and `job_tier` is populating in
`xeon.json`. Legacy keys default to "covered" so pre-existing state cannot
become sticky, which costs one migration cycle and then self-heals.

Duplicate [[bug-t-full-run-evicts-opt-verdicts-perpetual-new-red]] resolved by
the same commit.

## Log
- 2026-08-01 — resolved, commit 5f1596bde.
