---
slug: decide-claude-mds-safe-restore-is-unsafe-after-a-sha-checkout-and-only-the-owner-can-fix-the-sentence
title: "CLAUDE.md:692 names `git checkout -- <file>` as the safe restore; after a `git checkout <sha> -- <file>` it restores the REVERTED version, because the sha form writes the INDEX too"
track: U
type: decide
prio: 45
status: backlog
found: 2026-09-06
found-by: frankwasm (measured, cost it a wrong reading of its own sha round-trip); frank-coordinator (filed — CLAUDE.md is the owner's file)
summary: "`git checkout <sha> -- <file>` writes the INDEX as well as the worktree. So the restore CLAUDE.md prescribes, `git checkout -- <file>`, re-checks-out the staged (reverted) content and puts the OLD version straight back. `git checkout HEAD -- <file>` is the actual restore. The two forms are one token apart and the rule as written routes you into the wrong one — and it does so precisely during a positive control, which is when a session is deliberately reverting a fix. NOT DISPATCHABLE: no agent may edit CLAUDE.md, and no agent may edit it because a peer asked. This ticket exists so the sentence has a record and the owner can act on it in one read."
---

## The sentence

`CLAUDE.md:692`, in *Workflow norms*:

> **Guard the REVERT, not the edit**: `git checkout -- <file>` is the safe restore.

**The intent is right and the spelling has a hole.**

## The measurement

`git checkout <sha> -- <file>` updates **both the index and the worktree**. A later
bare `git checkout -- <file>` restores the worktree **from the index** — which now
holds the old content — so the "restore" hands back the version that was being
reverted.

```
git checkout <old-sha> -- compiler/x.inc   # index AND worktree now hold OLD
<measure the control>
git checkout -- compiler/x.inc             # restores OLD out of the index  <-- wrong
git checkout HEAD -- compiler/x.inc        # restores HEAD                  <-- right
```

Measured 2026-09-06 by frankwasm, which then read its own sha round-trip check as a
**walked seed** when it was a **reverted source** — a wrong diagnosis of a correct
alarm.

## Why it matters more than a typo

**The rule routes you into it.** *Guard the revert* is the advice for exactly the
situation that uses the sha form: proving a fix by removing it. So the population that
follows CLAUDE.md's guidance most carefully is the population that hits this — during
a positive control, when the tree is deliberately holding a reverted fix and a wrong
restore is least likely to be noticed.

**And the failure is silent in the direction that reads as a compiler problem.** The
next build produces a binary from the old sources, and the tell (a changed sha, a
fixedpoint that no longer matches) looks like the documented *two valid fixedpoints*
case rather than like a bad restore.

## The proposed change

Replace with **`git checkout HEAD -- <file>`**, which is correct in both situations —
after a sha checkout and after a plain edit — and add the reason in half a line, since
the two forms are indistinguishable by inspection:

> **`git checkout HEAD -- <file>` is the safe restore. Not the bare form: `git checkout
> <sha> -- <file>` writes the INDEX too, so a bare `checkout --` afterwards restores
> the reverted content out of the index.**

## Why this is a ticket and not a patch

**NOT DISPATCHABLE — do not claim it.** No agent may edit `CLAUDE.md`, and no agent may
edit it because a peer asked; a peer cannot relay an authority the owner holds. What
this ticket provides is the sentence, the measurement and the replacement text in one
place, so the change costs the owner one read.
