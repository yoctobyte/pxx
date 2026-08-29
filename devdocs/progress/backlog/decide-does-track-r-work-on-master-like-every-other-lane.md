---
slug: decide-does-track-r-work-on-master-like-every-other-lane
title: "Does Track R work on master like every other lane?"
track: U
type: decide
prio: 60
status: backlog
found: 2026-08-30
found-by: frankD
blocked-by: []
supersedes:
  - decide-what-happens-to-the-136-commit-rust-branch
  - decide-should-the-rust-topic-branch-be-retired-onto-master
summary: "Collapses two tickets that asked one question, both priced off a divergence that has moved. origin/rust is 136 ahead of master and master is 418 ahead -- but git cherry reports 122 of the 136 already have patch-equivalents on master, and 14 is an upper bound (two spot-checks of the 14 are demonstrably present). So the fork is not 'what do we do with 136 stranded commits'; it is 'does Track R work on master, and do we merge or drop at most 14 mostly-paperwork commits'. Prior recommendation, unchanged: retire the branch."
---

# Does Track R work on `master` like every other lane?

**Filed by frankD 2026-08-30, collapsing two tickets that asked the same
question.** The forks are unchanged and still the owner's; what changed is the
price, and the price is why this sat.

Superseded, preserved in `rejected/` with redirect notes:
`decide-what-happens-to-the-136-commit-rust-branch` (p60) and
`decide-should-the-rust-topic-branch-be-retired-onto-master` (p45). **The
analysis in both is theirs and still good** — the topology argument, the
`stable_linux_amd64/**` binary-conflict reason the topology does not extend to
A/B, and the `origin/wasm` comparison are all worth reading there. Only the
measurement changed.

## The measurement, at `64758a5c2` on 2026-08-30

The p60 ticket says *"origin/rust holds 136 commits of divergent work while
origin/master is 222 ahead."* The p45 ticket says *"8 ahead and 57 behind."*
Both are stale, in opposite directions. Today:

```
git rev-list --left-right --count origin/master...origin/rust   ->  418  136
git cherry origin/master origin/rust | grep -c '^-'             ->  122
git cherry origin/master origin/rust | grep -c '^+'             ->   14
```

**122 of the 136 already have patch-equivalents on `master`.**

**And 14 is an upper bound, not the answer.** `git cherry` matches by patch-id,
so anything that landed on master with a different conflict resolution, a
rebase, or an amended message reads as absent. Two of the 14 are demonstrably
present:

- `{$NILCHECKS}` documentation — on master today, 6 hits in
  `docs/reference/directives.md` and 2 in `docs/reference/modes.md`.
- the for-loop bounds fix — on master as `8b35e88fa`.

So the honest statement is **at most 14 outstanding, and the two I checked were
both false positives.** Anyone acting on this should re-run the three commands
above rather than trusting the numbers, which is the whole lesson of this
ticket.

Master pulling ahead 222 → 418 in the meantime is also evidence: the branch is
being kept in sync **into** `rust` and is not accumulating stranded work.

## Why the mis-pricing matters more than the correction

Nobody opens a 136-commit merge decision at 3am. **A number that rotted made a
cheap question look expensive, and the cost estimate is what people triage on,
not the question.** A Track U ticket does not have to be wrong to be
unanswerable; it only has to be priced wrong. The old slug carried the stale
number *in the slug*, which is the one place a reader cannot avoid it — that is
why this ticket has a new slug rather than an edit.

## The fork

**Does Track R work on `master` like A, B, C, N and D, or keep a topic branch?**

1. **Retire the branch; Track R works on `master`** (recommended by the p45
   ticket, and nothing measured since argues against it). Restores CLAUDE.md's
   one-branch rule, puts R's work in Track T's matrix immediately, removes the
   merge ceremony. R's files are disjoint from every other lane's, and its work
   has not been destabilizing — no new AST node, IR op, symtab field or backend
   edit, self-host fixedpoint green at each commit.
2. **Keep the branch with a mandatory merge-in cadence.** Preserves the
   2026-08-27 per-topic topology. The cadence is a discipline nobody can
   enforce, and `origin/wasm` at 312 behind is what happens when it lapses.
3. **Keep it and accept the drift.** Honest, and the status quo. R's work stays
   outside the test matrix indefinitely.

**And the sub-question, which is now small:** merge, cherry-pick, or drop the
**≤14** commits without a patch-equivalent on master. At this size an audit is
an afternoon, not a project — which is what the old framing obscured.

## What is NOT in scope

`origin/wasm`, at 76 ahead and 312 behind, with shared-file arms already
ledgered in `feature-a-merge-the-wasm-branch-the-shared-file-arms` [A p40].
**Branch permission is not merge permission**, for either branch. Whatever is
decided here probably wants to apply to both, but `wasm` has not had this
measurement run against it and should not inherit a verdict earned by `rust`'s
numbers.
