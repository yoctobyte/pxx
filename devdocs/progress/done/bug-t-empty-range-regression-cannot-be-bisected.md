---
summary: "When a run's parent_tested IS the tested sha, the regression's range is empty and idle bisect can never narrow it — so those tickets sit until a human bisects by hand"
type: bug
track: T
prio: 55
status: done
owner: claude-T@plexus
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

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.

---

## Resolution (Track T, 2026-08-08) — commit `315029d55`

All three parts of the fix shape, as specified.

1. **`last_covering_sha()`** — when the parent range is empty, fall back to the
   newest earlier run whose tier certainly *contained* this job. A run at tier
   E holds every job of the tiers E nests over, and the job just appeared at
   `tier`, so any earlier run with `tier in covered_tiers(E)` had it.

   Deliberately **conservative**: an earlier, narrower run may also have held
   the job, and skipping it only widens the range. A too-wide range costs
   bisect steps; a too-narrow one can exclude the culprit, which is the failure
   that matters. `opt` being disjoint means only an earlier `opt` run answers
   for an `opt` job — exactly why `optdiff#shard8-12` went unattributed.

2. **Ledger entries record the derived sha as `good`**, not the host's
   last-tested sha, so the entry and its range agree.

3. **`range_note()`** — the stub says what is true. With no range it reads
   "range **unknown** ... **no idle bisect will happen**; this one needs
   hand-triage" instead of promising a bisect nobody will run.

### Gate

`gate.sh quick` GREEN. Unit tests over the range derivation — parent range
empty → last covering run; the same-sha re-test skipped; `opt` isolated to
`opt`; no history → None — and over both stub texts.

**Coverage limit, stated plainly:** the two new pure functions are unit-tested,
but the call site inside `test_sha()` is not — exercising it needs a live clone
with a multi-run history, which the ticket's gate did not ask for and which no
existing devtest harness covers. The guard itself is two lines
(`if new_red and not rng:`), and the non-empty-parent-range path is unchanged
by construction: the fallback cannot run when `rng` is truthy.

### Surfaced while gating, filed separately

Routing `gate.sh` through `selfhost_fixedpoint.sh` (previous commit) means it
now also asserts the hermetic fixedpoint equals `compiler/pascal26` — strictly
stronger, and correct. But it reads the **live mutable path**, so a concurrent
build in the same clone flips it red transiently. Seen once here with 17 other
build processes on the box; GREEN on re-run with `make` reporting "up to date".
Filed as [[bug-t-gate-sh-fixedpoint-reads-the-live-mutable-compiler]] — testmgr
already snapshots the compiler per run for exactly this reason.
