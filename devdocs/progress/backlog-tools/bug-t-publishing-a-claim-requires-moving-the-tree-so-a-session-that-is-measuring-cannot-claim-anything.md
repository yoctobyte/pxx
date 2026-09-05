---
slug: bug-t-publishing-a-claim-requires-moving-the-tree-so-a-session-that-is-measuring-cannot-claim-anything
title: "A claim is only published by a folder move, which is a push, which is a rebase — so a session running a long measurement is structurally unable to claim"
track: T
type: bug
prio: 35
status: backlog
found: 2026-09-06
found-by: frankB (the incident and the found-by reading), frank-coordinator (the coupling, measured in tools/progress.py)
summary: "`working/` is not in RANKED_STATUSES, so moving the folder is the ONLY act that removes a ticket from `ready`/`next` — `owner:` does not affect ranking and its body-bullet spelling collapses into the same field. Publishing that move is a commit and a push, and a push is a `pull --rebase`, which is the one act forbidden while your tree is the instrument for a running measurement. So the longer a session measures, the longer it holds an unpublishable claim, and every other session's tools CORRECTLY report the ticket free. `_warn_claim_is_local` already diagnoses this and names the legitimate hold; it offers no channel, so the claim's only remaining home is a peer message and whichever seat happens to be awake."
---

## The machinery, read rather than assumed

- `RANKED_STATUSES = ("backlog", "backlog_new", "unfinished", "urgent") + backlog-*`
  (`tools/progress.py:961`). **`working` is not in it** — so `ready_tickets()` drops a
  ticket the moment it moves, and the FOLDER MOVE is the whole mechanism.
- `Ticket.owner` falls back to `first_bullet_value(self.text, "Owner")`, so a body
  bullet and the frontmatter key are **one field with two spellings**. Writing the
  claim "in the body instead" changes nothing a reader or the ranker can see.
- `owner:` is read by `check` (`STALE-PARK-HELD`) and displayed. It does **not** enter
  `ready`, `next` or the sort. An owned ticket left in a backlog folder still ranks
  and `next` still hands it out, with no marker — `unfinished` gets
  `[parked — re-claim, do not duplicate]` and a claim gets nothing, because a claim is
  expected to have moved.
- `cmd_claim` does the move, sets `Status`/`Owner`, `git add`s, and prints that it is
  **staged, not committed**. `_warn_claim_is_local` then says the claim is invisible
  until it lands, checks origin for a conflicting claim, and **explicitly refuses to
  push on the author's behalf** — its own docstring names the reason: *"there are
  legitimate holds (avoiding a rebase under a running gate, for one)."*

**Every step of that is correct.** The tool knows the failure mode, names it, and
declines the one act that would be wrong. At the end of the chain there is nowhere to
put the claim.

## Two instances, two different mechanisms, one night

1. **A p70 regression claimed by message.** The claimant could have published and had
   not yet. The coordinator held the fact and declined to write `owner:` on the
   claimant's behalf, because from a seat that must not dispatch, writing `owner:`
   reads as an assignment. A second session read the blank correctly and was one step
   from editing the same two functions. **Vocabulary arm: the only field available
   means "assigned" as readily as "doing".**
2. **A two-ticket group claimed by message the same night.** The claimant `claim`ed
   both and could not publish: its tree was the instrument for a `make -k test-core`
   ~51% through, and `tools/sync.sh` does `pull --rebase`. Moving the tree under the
   run would have destroyed the measurement — the CLAUDE.md rule *DO NOT TOUCH THE
   INSTRUMENT WHILE IT IS MEASURING*, obeyed correctly. **Publication arm: the claim
   channel is coupled to the working tree.**

The second is not a discipline problem and no amount of remembering to write it down
fixes it: **the session with the most valuable claim to publish — the one holding a
tree for an hour — is the session least able to publish it.**

## Why a new `claimed-by:` field was the wrong remedy

It was the first proposal and the machinery above kills it: a new frontmatter key
that nothing ranks on is invisible for the same reason `owner:` is, and it would still
need a commit and a push to reach anyone.

**`found-by:` is the existing proof that a name can be recorded without reading as a
dispatch** — it is written by whoever files, names a session, and nobody has ever read
it as an assignment. So the vocabulary arm is smaller than a new convention: **`owner:`
is overloaded to mean both "who is doing this" and "who is assigned this", and only
the second is what a non-dispatching seat must not write.** Splitting the first out is
a rename of something that already exists.

## Recommendation

- **Vocabulary:** split "doing" from "assigned" so a coordinator relaying a claim
  writes a fact rather than an order. `found-by:` is the shape to copy.
- **Publication:** give `claim` a way to reach origin **without moving the working
  tree** — the claim is a one-file change and does not need a rebase of the tree that
  is measuring. Whatever the mechanism, the requirement is that it costs a measuring
  session nothing.
- **Until then**, `_warn_claim_is_local` should say what to do, not only what is
  wrong: an unpublishable claim goes to a peer as a message, and the message is the
  claim until origin catches up. That is what both instances actually did, and it
  worked only because the sessions involved happened to be awake.

## The general form

**A blank field speaks.** A field left blank on purpose and a field never filled in
are indistinguishable at the reader, and the reader has less information than the
person who left it blank. When writing something down would carry the wrong meaning,
declining to write it does not avoid the meaning — it moves the ambiguity onto the
reader. See `devdocs/dev/debugging-playbook.md`, *A FIELD LEFT BLANK ON PURPOSE AND A
FIELD NEVER FILLED IN ARE INDISTINGUISHABLE AT THE READER*.
