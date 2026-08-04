---
summary: "When a run's parent_tested IS the tested sha, the regression's range is empty and idle bisect can never narrow it — so those tickets sit until a human bisects by hand"
type: bug
track: T
prio: 55
---

# An empty range is unbisectable, and the two-phase watcher produces them

- **Type:** bug (Track T — `tools/twatch.py`, the ledger + idle bisect)
- **Found:** 2026-08-04 by `claude@xeon` — three separate instances in one
  session, which is what makes it structural rather than bad luck.

## The mechanism

`publish()` computes the commit range as `commits_between(parent, sha)` where
`parent` is the host's previously tested sha. The two-phase watcher deliberately
re-tests **one** commit at a widening tier — native first for speed, then the
full/opt backfill when the repo goes idle — so on the second pass
`parent_tested == sha` and the range is **empty**.

The existing rule then does the right thing with what it has:

```
twatch: N new red at <sha> but 0 commits since the last tested sha —
        not localizable; recording job status only
```

No ledger entry is opened, because an entry naming no commit is unbisectable
and unfalsifiable. But a stub TICKET is still filed, and it carries
`0 commit(s) in range — the watcher narrows this by idle bisect`, which is a
promise nothing can keep: with no entry in `open_regressions`, `bisect_step`
never sees it.

## The three instances, all this session

| ticket | tier | cost |
|---|---|---|
| `regression-test-nilpy-test-nilpy-class-return` | full | bisected by hand to `86b0fc2b7` |
| `regression-test-nilpy-print-arg-eval-order` | full | hand-triaged; was a test-file collision |
| `regression-optdiff-shard8-12` | opt | **sat 2 days**; hand-attributed to `2dbce8a2e` |

The last one is the cost in plain form: a real -O3 miscompile (the timezone
offset silently vanishing) sat unattributed for two days with a stub ticket
claiming a bisect was coming.

## Why the range is empty rather than absent

The information is not missing — it is in the wrong place. A job that reds in
the FULL tier at sha X was last green in the full tier at some earlier sha Y,
and `job_tier` already records which tier last spoke for each job. The range
that matters is `Y..X` — "since this job last ran and passed" — not "since this
host last tested anything".

## Fix shape

1. When the parent-based range is empty, fall back to the **per-job** range:
   the newest sha at which a run COVERING that job's tier reported it passing.
   `history` carries per-run sha/tier, so the lookup is local.
2. Only then decide whether to open a ledger entry. A job whose per-job range is
   also empty (first run at that tier) still gets today's treatment: status
   only, no entry, no false promise.
3. The stub ticket must not claim a bisect that cannot happen — say
   `range unknown (first full-tier run at this sha)` rather than
   `the watcher narrows this by idle bisect`.

## Gate

`--tier quick` green plus a devtest over the range derivation: parent range
non-empty -> unchanged; parent range empty but the job passed at an earlier
sha in a covering tier -> that range; neither -> no entry and no bisect promise
in the stub text.
