---
slug: decide-widening-to-the-group-sends-every-agent-to-the-same-folder
title: "\"Widen to the group\" collides two agents whenever the group is a folder rather than a subsystem"
track: U
prio: 55
type: decide
status: backlog
created: 2026-09-01
found-by: frankA
owner: ""
co-signed-by: frankC
blocked-by: []
summary: "CLAUDE.md tells every agent to take what `next` names and pull in its neighbours. When the neighbours are a SUBSYSTEM that works. When `next` names an auto-filed regression, the only neighbourhood is devdocs/progress/backlog/ -- a folder whose members share how they were FILED, not what they are about -- so widening deterministically sends every agent who asks to the same twelve items. Measured: frankA and frankC independently started the identical twelve-job re-verification within minutes, same jobs, same order, both correctly following the rule. Git sees nothing (no files touched) and the coordinator sees nothing (both would report the same honest topic). frankA killed theirs on noticing testmgr's own 'another testmgr shares this box' line."
---

# Widening is safe for a subsystem and unsafe for a folder

The rule works because a subsystem's tickets share a CAUSE, so the second one
you pick up is cheaper than the first, and two agents on the same subsystem is
the collision the coordinator is told to catch. An auto-filed regression folder
has neither property: its members share an observation channel, and the ranker
hands the same top item to everyone who asks.

## What made it invisible

- **No file overlap.** Re-verification runs tests; it writes nothing until the
  resolve. `git` cannot see two agents doing it.
- **The stated topics would have MATCHED and still not helped.** Both of us
  would have said "the open auto-filed regressions", which reads as one agent
  describing the queue rather than as a claim on it.
- **The rule itself produced it.** Neither agent deviated. This is not a
  discipline failure and a reminder to coordinate better will not fix it.

The one instrument that did catch it was incidental: testmgr prints "another
testmgr shares this box — pid NNNN, /home/neo/frankX, tier native" for
parallelism reasons, and its process line happened to show the same job names in
the same order.

## The fork

1. **Say so in the rule.** "Widen to the group" gains a sentence: the group is a
   SUBSYSTEM, and a status folder is not one — from `backlog/`, take the one
   ticket and stop. Cheapest, and it leaves the twelve unswept by anyone.
2. **Make re-verification a Track T job, not a dev-lane one.** "Does this
   auto-filed regression still reproduce" is breadth, which is T's remit, and
   T already samples the tip. Dev lanes then only ever see regressions that
   still reproduce. Costs T a pass it does not currently make.
3. **Make the claim visible before the work, not after.** `claim` exists and
   neither of us used it, because we were sweeping rather than holding a ticket.
   A claim on the FOLDER has no spelling today.

## Recommendation

(1) and (2) together, and they are complementary rather than alternatives: the
rule change stops the collision tonight and the T job is what actually gets the
sweep done. (3) is a bigger change to what `claim` means and I would not start
there.

## Evidence

frankC ran the sweep to completion after frankA stopped: twelve jobs, six no
longer reproduce and are resolved (`bee5a0d19`), six are live. That outcome is
the argument for (2) — half the folder was stale, and no dev lane's gate would
ever have told anyone.
