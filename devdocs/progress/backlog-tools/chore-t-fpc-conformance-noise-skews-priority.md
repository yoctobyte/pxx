---
track: T
prio: 50
type: chore
status: backlog
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "FPC-testsuite conformance failures auto-file into Track T's backlog at prio 70 by FALLBACK lane, because the failing recipe names `tools/run_pascal_conformance.sh` and no owner. The suite is a gap-measuring corpus — 170 entries in pxx.skip, failing is its expected state for unimplemented features — so an FPC gap now outranks real work in T's queue, and because the shards run in `full` they also enter the pin-shadow's blocking set. Owner direction 2026-09-01: FPC compliance is lower priority and running FPC's tests skews priorities. Needs an owner pick between four options; two are cheap."
---

# FPC conformance failures land at prio 70 in Track T and skew the queue

## The mechanism

`test-pascal-conformance#shard*/6` runs `tools/run_pascal_conformance.sh`, a
Track T script. When a shard goes red the autoticket filer looks for an owner
in the failing step, finds none, and falls back to **Track T at prio 70**. The
stub says so itself:

> *Track T by default: the FAILING STEP named no owner. … This is a FALLBACK,
> not a finding — nothing says the defect is Track T's. Re-lane it before
> working it.*

Nobody re-lanes it. Current state of the four filed:

| ticket | prio | track |
|---|---|---|
| `regression-test-pascal-conformance-shard0-6-4` | 45 | P *(re-laned by hand 2026-09-01)* |
| `regression-test-pascal-conformance-shard1-6-2` | 70 | T |
| `regression-test-pascal-conformance-shard2-6-2` | 70 | T |
| `regression-test-pascal-conformance-shard3-6-2` | 70 | T |

So three Pascal-frontend gaps sit above almost everything real in Track T's
backlog, attributed to a lane that cannot fix them.

## Why this corpus is the wrong shape for a regression filer

`test/pascal-conformance/pxx.skip` has **170 entries**. The suite measures a
known gap list against FPC; for unimplemented features, failing is the expected
state, and the skiplist is the record of which failures are accepted. A test
crossing from "skipped gap" to "unskipped failure" is therefore routine
corpus movement, not necessarily a regression — but it files identically to a
real one, at the same prio, in the same lane.

`shard0/6` is a live example of both at once: one genuine compiler regression
(`tgeneric32.pp`, specialization anchoring) and one known-gap construct that is
already waived for its sibling `tgeneric50.pp` (`tgeneric49.pp`, hint directive
on a generic). Same ticket, same prio, different truths.

## Second effect: the pin shadow

The shards run in `full` only, and `full` is `PIN_TIER` — the only tier that may
qualify a pin. So every unskipped conformance failure enters
`pin_shadow()`'s `unexpected` set and shows up in `pin-shadow.log` as a reason
the gate "would NOT pin". `test-pascal-conformance#shard0/6` is precisely what
ended an 81-decision run of `WOULD PIN` on 2026-08-31T05:36Z.

This does **not** block pinning — `would_pin` has no deciding consumers and
`pin_shadow()` moves nothing (see `a44a28aab`). But it is read as if it did, and
an FPC gap is a poor reason for the pin advisory to read red.

## Options — owner picks

1. **File conformance regressions to `track: P` at a low prio** instead of the
   T fallback. Smallest change; fixes the queue skew directly. The filer already
   knows the target name, so the lane can be a per-target rule rather than a
   guess.
2. **Add the conformance shards to `devdocs/progress/tstate/pin-allowlist.tsv`**,
   each naming this ticket. That is exactly the designed mechanism — "reds listed
   here do NOT block an automatic pin", every entry must cite a ticket — and it
   takes FPC gaps out of the pin advisory without hiding them.
3. **Demote the shards out of `full`** into an idle lane, so they stop
   contributing to per-sha verdicts and to the pin tier at all. Keeps the
   coverage, loses the promptness.
4. **Stop running the suite.** Cheapest noise reduction, largest coverage loss.

**Recommendation: 1 + 2.** Both are small, neither loses coverage, and together
they address the stated complaint — FPC results stop competing with real work
for priority and stop colouring the pin advisory. 3 and 4 trade away coverage to
solve a routing problem.

## Not to be confused with

The conformance suite itself is fine and its output is accurate. Nothing here
argues the shards are wrong; the defect is where their results are *filed* and
what they are allowed to gate.
