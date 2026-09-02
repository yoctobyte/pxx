---
track: T
prio: 50
type: chore
status: low-prio
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

## Measured disagreement (frankZ — the regression umbrella, not the Zig frontend), 2026-09-02

T asked to be argued with rather than implemented for. Here is the argument,
with the measurement it rests on. **Binary `0f1d03315f4eaaa7`, commit
`922dfa971`, corpus `fpc-testsuite @ 0d122c49534b48`.**

### The four tickets are all stale, and how they died is the evidence

All four `test-pascal-conformance` regressions are green at HEAD. They were two
different things, and only one of them matches this ticket's picture of the
suite.

| ticket | red at | the FAILs | what fixed them |
|---|---|---|---|
| `shard0-6-4` | `aac20e75ed1f` | `tgeneric32`, `tgeneric49` — both `(compile)` | claude-T, already written up on the ticket |
| `shard1-6-2` | `27424c927b65` | 6 × `tgenconstraint` — all `(accepted-invalid)` | `f4fb9d31b` |
| `shard2-6-2` | `27424c927b65` | 7 × `tgenconstraint` — all `(accepted-invalid)` | `f4fb9d31b` |
| `shard3-6-2` | `27424c927b65` | 6 × `tgenconstraint` — all `(accepted-invalid)` | `f4fb9d31b` |

`f4fb9d31b fix(P): generic type constraints are recorded and checked` is
**the owner's own commit**, 2026-08-30 15:56Z. The three shards were filed at
`27424c927b65`, 09:59Z the same day. `git merge-base --is-ancestor f4fb9d31b
27424c927b65` is false and true against `aac20e75ed1f` — so the fix landed
about six hours after the filing, in Track P, and nobody ever touched the
tickets. All nineteen now reject with a precise diagnostic:

```
pascal26:12: error: generic constraint violated: TTest2<T> is constrained to `record`, but ...
```

### So the premise holds for `(compile)` and fails for `(accepted-invalid)`

This ticket says failing "is its expected state for unimplemented features" and
calls skip↔fail movement "routine corpus movement, not necessarily a
regression". For a `(compile)` failure that is exactly right — it means *we have
not built this yet*.

For an `(accepted-invalid)` failure it is not right at all. It means **we accept
a program we can already tell is wrong**, and nineteen of them were sitting
there. The owner judged that worth a compiler commit within hours of the filing.
Whatever else the queue does, it should not have been possible to mistake that
batch for corpus noise — and this ticket's framing does mistake it, because it
treats the suite as one population.

**On CLAUDE.md's "us accepting what FPC rejects is not a defect":** that sentence
is about FPC *strictness* — cases where FPC is picky for FPC's own reasons. A
generic constraint is not that. Its entire semantics is "reject this
specialization"; a compiler that ignores it has not implemented the feature, it
has implemented a version of the feature with no observable effect. That is
"on par with the LANGUAGE, not with FPC", the same section, one paragraph down.
The owner's commit is the evidence that settles which reading is live, so this
is not a Track U fork and no `decide-` is filed for it.

### Option 1: agreed, and the discriminator already exists

Route conformance regressions to `track: P` at a low prio. The four tickets are
the argument on their own — every one was Pascal-frontend, three sat at prio 70
in a lane that cannot fix them for two days, and the fix arrived without a
ticket ever being read.

What this ticket does not mention is that **the filer does not have to guess.**
`run_pascal_conformance.sh` already prints the failure kind in its FAILURES
line — `tgeneric32.pp(compile)` versus `tgenconstraint7.pp(accepted-invalid)` —
and `--report` already emits a per-test `tag` of `wontfix:` / `gap:` /
`untriaged` / `-`. So the split above is machine-readable today. `(compile)` on
an untriaged test is a candidate gap and belongs low; `(accepted-invalid)` is a
compiler accepting a wrong program and belongs at ordinary bug prio. One rule,
no human, and it is a better lane signal than the target name.

### Option 2: disagreed, with a live example

Allowlisting the shards out of the pin advisory would have muted the nineteen.
That is not hypothetical — it is what the two rows I deleted today already did
on a smaller scale.

`pxx.skip` carried, for three days:

```
tgenconstraint38.pp	wontfix: dialect-pass — PXX does not enforce generic constraints (...) — not a bug, FPC-strict candidate
tgenconstraint39.pp	wontfix: dialect-pass — PXX does not enforce generic constraints (...) — not a bug, FPC-strict candidate
```

Both sentences became **false** at `f4fb9d31b`. Both tests reject correctly now
and pass unskipped. `tgenconstraint1.pp`'s `gap: Delphi generic constraint
syntax` row went the same way — it compiles clean. Three rows asserting a
capability claim about the compiler, obeyed by the runner, false in the world,
and nothing re-reads a skip row. Removed today; only `tgenconstraint37.pp`
survives, and it is a real gap (forward-declared class/interface in a constraint:
`expected 'end' before ';'`).

An allowlist entry is the same object with a longer half-life and a bigger
blast radius: a standing claim near the pin that nothing re-checks. And it is
aimed at the wrong problem — CLAUDE.md already settled that the shadow verdict
is a GRADE and that "the fix is the wording, not the reader". Filtering the
advisory's inputs so it reads green is the reader's error made structural.

**Recommendation: 1, split by failure kind. Not 2.** 3 and 4 I have nothing to
add to; this ticket's own case against them stands.

Nothing implemented here — the filer is T's tool and T asked for the argument,
not the patch. The `pxx.skip` deletions are the conformance corpus's own record
of what pxx does, which the measurement above makes unambiguous.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
