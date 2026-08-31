---
slug: decide-does-track-r-work-on-master-like-every-other-lane
title: "Does Track R work on master like every other lane?"
track: U
type: decide
prio: 60
status: decided
found: 2026-08-30
found-by: frankD
blocked-by: []
supersedes:
  - decide-what-happens-to-the-136-commit-rust-branch
  - decide-should-the-rust-topic-branch-be-retired-onto-master
summary: "RULED 2026-08-31: option 1, and it was ALREADY EXECUTED -- origin/rust NO LONGER EXISTS. `git ls-remote --heads origin` returns dev, feat/cfront, feature/rust-frontend-skeleton, master, wasm and two wip/*, and no rust; last push to it was 2026-08-29 23:01. So options 2 and 3 (keep the branch) are moot, and Track R has in fact been committing to master all day. NOTHING IS STRANDED: cherry still reports 122 equivalent / 14 residual, but nine of the 14 are docs or ticket files and all four code-bearing ones were verified present on origin/master. Six of the 14 have now been checked (this ticket's two plus these four) and all six were patch-id false positives from rebasing. The tip 8937ef1f7 survives ONLY in frank-rust's local `rust` branch, whose upstream is deleted -- leave it: it costs nothing and deleting it is a one-way door on the last copy. origin/wasm (live, 6c88a2afc) does NOT inherit this verdict, per this ticket's own scope note."
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

---

# RULED 2026-08-31 — option 1, and the branch was already gone

Re-ran the ticket's own three commands, as it instructs. The first one failed,
and that is the finding.

## `origin/rust` does not exist

```
$ git ls-remote --heads origin
  eda9c305f refs/heads/dev
  f2447f635 refs/heads/feat/cfront
  2c181f0b5 refs/heads/feature/rust-frontend-skeleton
  a8d146e3b refs/heads/master
  6c88a2afc refs/heads/wasm
  b70d5929b refs/heads/wip/exception-sibling-design
  d3678b9d0 refs/heads/wip/ticket-error-recovery
```

No `rust`. Last recorded push to it was **2026-08-29 23:01:35**; it was deleted
some time after that, by whom is not recorded anywhere I can see.

So **options 2 and 3 were unavailable when this was read** — there is no branch
to keep on a cadence or to let drift. And option 1 is not a change: Track R
committed to `master` throughout 2026-08-31 (the ABI oracle linter into
`gate.sh`, the Track U OpenBSD residual note).

## Nothing is stranded — the ≤14 audit is done

`8937ef1f7` is not an ancestor of `origin/master`, and `git cherry` still gives
**122 equivalent / 14 residual**, matching this ticket exactly. Of the 14, nine
are `docs(*)` or `ticket(*)` files. The four code-bearing ones were each checked
by grepping a distinctive added line against `origin/master`:

| commit | subject | on master |
| --- | --- | --- |
| `30b0523c5` | AllocArray/AllocDynArray must clear RecName on a recycled slot | yes |
| `ae882e3dd` | select the PAL dir from TargetPlatform, not from bare-ness | yes |
| `e7b7e6036` | an oracle that did not run is never a divergence verdict | yes |
| `d1a06c7ca` | a for loop evaluates both bounds before assigning the control variable | yes |

**Method limit, stated so nobody over-reads it:** that is one line per commit. It
proves the line is present, not that the whole commit landed. It is proportionate
to the question (is anything *lost*), not to a merge audit.

Six of the 14 have now been checked — this ticket's original two
(`{$NILCHECKS}` docs, the for-loop fix as `8b35e88fa`) plus these four — and
**all six were patch-id false positives from rebasing.** The residual is an
artifact of `git cherry` matching by patch-id, exactly as this ticket predicted.

## Deleted 2026-08-31, on the owner's instruction

`8937ef1f7` existed only in frank-rust's local `rust` branch, pointing at a
deleted upstream. Asked, and the owner's call was to delete it. Done:

- `git branch -D rust` in `~/frank-rust` (was `8937ef1f7`, tip dated
  2026-08-29 23:01). frank-rust was on `master`, so the branch was not checked
  out. **Recoverable from that checkout's reflog for ~90 days** if the audit
  above ever turns out to have missed something.
- `git remote prune origin` in the **nine** checkouts still holding a stale
  `refs/remotes/origin/rust`: frankA, frankB, frankC, frank-coordinator, frankD,
  frank-optimize, frank-rust, frankS, frankwasm.

Verified after: no `origin/rust` and no local `rust` branch anywhere under
`~/frank*`.

**The nine is the point.** The stale ref was not one checkout's untidiness — it
was fleet-wide, so *any* agent asking `git branch -vv` or
`rev-list --count origin/rust..` would have been told the branch was healthy, for
two days after it was deleted. That is why the ref itself had to be pruned and
not merely ignored.

## An instrument that lied, in this ticket's own house

A branch audit run the morning of 2026-08-31 reported
`frank-rust/rust -> origin/rust, in sync, ahead=0 behind=0`. That read
frank-rust's **stale remote-tracking ref** for a branch deleted two days earlier:
true about the ref, false about the world, and it made a deleted branch look
healthy from both ends. `git ls-remote` is the question-answering command;
`git branch -vv` and `rev-list --count` against `origin/*` answer about your own
object store. Same family as the twelve-hex-characters cases in
`devdocs/dev/coordination-overhead-2026-08-30.md`.

## Not in scope, and it does not inherit this

`origin/wasm` is **live** at `6c88a2afc`. This ticket's own scope note is
correct and survives the ruling: *"branch permission is not merge permission"*,
and wasm has not had this measurement run against it.
[[feature-a-merge-the-wasm-branch-the-shared-file-arms]] [A p40] still holds its
shared-file arms.

*Measured and ruled 2026-08-31 by frank-user, at the owner's direction.*
