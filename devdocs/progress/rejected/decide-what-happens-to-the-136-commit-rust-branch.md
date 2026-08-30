---
track: U
prio: 60
type: decide
status: superseded
blocked-by: []
found: 2026-08-29
found-by: frank-coordinator
summary: "origin/rust holds 136 commits of divergent work while origin/master is 222 ahead. A green Track P fix and two p65 tickets landed there tonight and were invisible to the whole fleet. CLAUDE.md says all tracks work on master and never a long-lived branch. Merge it, cherry-pick from it, or retire it -- the coordinator will not decide a 136-commit merge."
superseded-by: decide-does-track-r-work-on-master-like-every-other-lane
---

> **SUPERSEDED 2026-08-30 by `decide-does-track-r-work-on-master-like-every-other-lane`.**
> This ticket and its sibling asked one question, and both priced it off a
> divergence measurement that has since moved: `git cherry origin/master
> origin/rust` reports **122 of the 136 commits already have patch-equivalents
> on master**, only 14 do not, and 14 is an upper bound — two spot-checks of
> those 14 are demonstrably present on master. **Do not act on the numbers
> below.**
>
> Filed in `rejected/` because it is not the open question, **not because its
> reasoning is wrong** — the analysis below is preserved intact and is still
> the best writeup of the topology argument. Read it; re-measure before
> quoting it.


# What happens to the 136-commit `rust` branch?

**Escalated rather than guessed.** A branch merge of this size is a topology
decision with a blast radius, and *branch permission is not merge permission* —
the same rule that keeps `origin/wasm` unmerged. The coordinator has handled the
immediate damage and is not settling the rest.

## What happened

frank-rust resolved `bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized`
tonight — green, self-host fixedpoint verified, five table rows matching FPC,
two new tests with FPC-computed oracles. It pushed to `origin/rust`, reporting:

> *"`origin/master` is 135 commits behind and carries none of the fleet's recent
> work, including several other agents'. That looks like the current fleet
> topology rather than a mistake."*

**That reading was exactly backwards.** Measured:

```
git rev-list --left-right --count origin/master...origin/rust   →   222   136
git merge-base --is-ancestor 9a98d314c origin/master            →   NOT on master
```

`origin/master` is the trunk and carries the whole fleet's evening. So a green
fix, a third fix nobody had asked for (a fixed-point loop terminating early on a
false invariant, corrected on **both** arms), and two p65 tickets with
built-and-run repros were all invisible to every other lane and to Track T.

**Already handled, and needing no decision:** frank-rust has been told to
cherry-pick its own two commits onto `master` and to work there from now on.
That is re-landing its own green work on the trunk — ordinary, self-contained
(`Makefile`, three `pasparser_*.inc`, tests, tickets; 600 insertions, no shared
internals), and not a branch merge.

## The fork

**What becomes of the other ~134 commits on `origin/rust`?**

1. **Merge the branch.** Fastest if the work is wanted whole. But it is a large
   merge into a trunk that nine lanes are pushing to continuously, and nobody has
   audited what is in it — the same unknown-contents objection that keeps
   `origin/wasm` parked, and that branch has a five-arm ledger precisely because
   somebody did the audit first.
2. **Cherry-pick what is wanted, retire the rest.** Safest, and consistent with
   how tonight's fix is being recovered. Costs a review pass over 134 commits by
   someone who knows which Rust-frontend work is still live.
3. **Retire the branch and re-do the work on master.** Only sane if most of it is
   superseded — unknown without the audit in option 2.
4. **Sanction the branch deliberately** and give it a documented merge cadence,
   which would mean amending the one-branch rule rather than quietly breaking it.

**Recommendation: option 2.** It matches what is already in motion, it produces
the audit that options 1 and 3 both need anyway, and it does not require changing
a rule that was adopted for measured reasons.

## Why the rule exists, since option 4 would overturn it

`CLAUDE.md` is explicit: all tracks work on `master`, one branch, no worktrees or
clones; destabilising work goes behind a flag or lands incrementally, **never a
long-lived branch**. The `dev` branch was created 2026-08-25 and retired
2026-08-26 — nine syncs in under six hours, each spending a full gate run on the
box whose contention is the binding constraint on the test matrix.

Tonight cost a different price, and it is the one worth weighing here: **the work
was not merely unmerged, it was unseen.** Unpushed-to-trunk is untested — Track T
sweeps `origin/master` — so a green branch commit has no cross-target verdict, no
tstate entry, and no visibility to any lane that might duplicate it. The
coordinator only found it because frank-rust mentioned the branch in passing.

## A related question the owner may want to answer at the same time

`origin/wasm` is in the same category, with `feature-a-merge-the-wasm-branch-the-shared-file-arms`
[A p40] as its ledger — five arms across two lanes. Two long-lived branches is a
pattern rather than an accident, and whatever is decided here probably wants to
apply to both.
