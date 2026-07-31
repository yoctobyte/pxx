---
summary: "the xeon agent had no dev checkout, so its commits landed on the watcher clone's detached HEAD; protocol doc should say so"
type: task
track: T
prio: 55
---

# The watcher clone is not a dev checkout — xeon's agent needs its own

- **Type:** fleet protocol gap (found while proving the two-box protocol)
- **Found:** 2026-07-31 by `claude@xeon`, the day the p2p link went symmetric.

## What went wrong

xeon had exactly **one** checkout, `~/trackt-watch`, and it belongs to the
watcher daemon. The agent used it for ticket and code work because there was
nothing else. Three distinct failures followed, all from the same cause:

1. **`git pull --rebase` failed repeatedly** with *"cannot pull with rebase:
   You have unstaged changes"* — the daemon was mid-publish, writing tstate
   files, at the moment the agent tried to rebase.
2. **A commit landed on a detached HEAD.** The daemon checks out arbitrary shas
   to test them; between the agent's `git checkout master` and its `git commit`,
   the daemon had detached the tree again. The commit was fine but invisible —
   1 ahead of nothing, 4 behind origin, on no branch. It took a `cherry-pick`
   onto a re-attached `master` to rescue it.
3. **A push was rejected** because the clone's own daemon had pushed tstate in
   between. Recoverable, but it makes every agent push a race against the
   machine it is standing on.

None of this is the daemon misbehaving. `twatch` is documented to refuse a
dirty checkout precisely because it does detached checkouts of arbitrary shas —
it is protecting the agent. The mistake was using the watcher's clone as a
workspace at all.

## Already covered, but only halfway

`two-box-protocol.md` says:

> never run jobs inside the **peer's** `~/trackt-watch` while its daemon is
> live: it checks out shas underneath you and your run races its working tree

Exactly right, and it applies just as much to **your own** box's watcher clone.
The doc frames it as a courtesy to the peer; it is really a property of any live
watcher clone, including the local one. `CLAUDE.md` already implies the split —
*"Track T's watcher daemon runs in its own dedicated clone — it's infra, not a
dev agent"* — but nothing states the corollary that the agent therefore needs a
second checkout.

## Done on xeon

A normal dev checkout now exists at **`~/pxx`** (plain clone of origin,
`merge.ours.driver` configured). `~/trackt-watch` is the daemon's alone. This
ticket's own commits were made from `~/pxx`.

Layout is now the same shape on both boxes: agent works in a dev checkout,
watcher owns its dedicated clone, origin is the only shared state.

## NOT an argument for one checkout per box

Correction, user 2026-07-31: **borg's several checkouts are deliberate — the
split is per TRACK**, and the resulting untidiness is normal development, not
drift to be cleaned up. An earlier version of this ticket read like a call to
consolidate. It is not. Do not retire or merge borg's trees on the strength of
this ticket.

The rule here is narrower than "one checkout per box":

> a checkout with a **live watcher daemon** is infra and cannot also be a
> workspace, because it detaches HEAD underneath you.

That is a property of the daemon, not of having many checkouts. Per-track trees
are fine and can be as numerous as the tracks; a *watched* tree is the only one
that must be left alone. On borg the daemon is stopped, so `~/trackt-watch`
there is just another checkout. On xeon the daemon is live, so `~/trackt-watch`
is off-limits and `~/pxx` exists to work in.

Two consequences for anyone reading a filesystem:

- **Do not infer lane ownership from checkouts.** A tree being stale, dirty, or
  ancient says nothing about who holds a lane. `working/` on origin is the only
  answer to that — which is exactly what the sole-A guard in
  `two-box-protocol.md` already queries.
- Uncommitted work in a per-track tree is an agent working, not a lost commit.
  It is invisible to Track T until pushed, which is a fact about the offload
  model, not a defect in the tree.

## Ask

Fold the rule into `devdocs/dev/two-box-protocol.md` (borg's file — hence a
ticket rather than an edit from here):

- the watcher clone is **infra, never a workspace** — yours or the peer's;
- each box's agent works in its own dev checkout (`~/pxx` on xeon);
- if a commit ever ends up on a detached HEAD in a watcher clone, it is not
  lost: `git checkout master && git cherry-pick <sha>`.

Worth a line in `trackt setup` too — if it is pointed at a clone that turns out
to be the *only* checkout on the box, say so.
