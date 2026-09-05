---
slug: bug-t-a-commit-made-in-the-watcher-clone-during-a-gate-is-unreachable-from-any-ref
track: T
type: bug
prio: 50
status: backlog
found: 2026-09-06
found-by: seven (Upgrade to 26.04 verification), filed by frank-coordinator
owner: ""
blocked-by: []
summary: "The Track T watcher clone sits on a DETACHED HEAD whenever the daemon is mid-gate, because it checks out the sha under test. A commit made in that window is not merely unpushed -- it is unreachable from any ref (`git for-each-ref --contains <sha>` returns nothing) and one `git gc` from gone. Measured 2026-09-06 on seven: `038c3acf1` survived because the clone happened to be on `master` (`[ahead 2]`); `3815bee43`, same clone, same session, 90 minutes later, was born parentless of any branch. The repo's existing rule (`A LOCAL COMMIT IS NOT BANKING`) does not cover this, because the mitigation it prescribes -- remember to push -- never fires if you do not notice you were detached, and `git log --oneline -1` looks normal. The tell is one line: `git status -sb` printing `## HEAD (no branch)`."
---

# A commit made in the watcher clone during a gate is unreachable from any ref

## The measurement

Two commits, **same clone, same author, same session**, opposite outcomes:

| sha | clone state at commit time | outcome |
| --- | --- | --- |
| `038c3acf1` (`install_qemu.sh`) | `## master...origin/master [ahead 2]` | reached origin normally |
| `3815bee43` (`install_host_deps.sh`) | detached — daemon mid-gate | **`git for-each-ref --contains` returned NOTHING** |

The only difference was **what the daemon was doing at that moment.** Ninety
minutes apart.

## Why this is not the rule we already have

CLAUDE.md says *"A LOCAL COMMIT IS NOT BANKING"* — a session gets restarted and
the restart takes the commit with it. True, and it prescribes: push.

**Here the failure is upstream of pushing.** The commit is not on an unpushed
branch; it is on **no branch**. `git push` has nothing to name. And the
mitigation cannot fire, because:

- `git log --oneline -1` looks **perfectly normal** immediately after.
- `git status` (without `-sb`) shows a clean tree and says nothing about the ref.
- Nothing errors. The commit succeeds and prints a sha.

**Another instrument that lies by being correct about something else** — `git
log` is right about the object and silent about its reachability.

## The tell, and it is one line

```sh
git status -sb        # -> '## HEAD (no branch)'
```

Anything committing inside a Track T clone should check that **before** the
commit, not after.

## Recovery, as performed, without disturbing the daemon

Recorded because the obvious recovery (`git checkout master` in the clone)
**would have moved the daemon's working tree mid-gate** — this repo's *"do not
touch the instrument while it is measuring"*.

1. Protect the object with a throwaway branch first.
2. `git worktree add` on origin/master — a second tree, daemon untouched.
3. Cherry-pick (clean; the parent was already an ancestor).
4. Re-run the script's own `--check` **in the landed tree**, not the source one.
5. Rebase, push, remove the worktree and the branch.

Daemon's working tree and detached HEAD never touched; clone clean afterwards.

## Fix candidates, unranked

1. **A pre-commit hook in the watcher clone** refusing a commit on a detached
   HEAD, with the recovery above in its message. Cheapest, catches it at the
   only moment the author is present.
2. **The daemon restores `master` when idle**, so the detached window is exactly
   the gate rather than "since the last gate". Narrows but does not close it.
3. **Do not author in the watcher clone at all** — commit tooling from a normal
   checkout. Correct and unenforceable; the clone is where the box is.

(1) is the one that fires without anyone remembering anything, which is the
property this ticket exists for.
