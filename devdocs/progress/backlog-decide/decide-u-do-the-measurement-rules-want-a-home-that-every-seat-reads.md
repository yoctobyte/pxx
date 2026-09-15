---
type: decide
track: U
prio: 60
status: open
slug: decide-u-do-the-measurement-rules-want-a-home-that-every-seat-reads
---

# Do we want one set of measurement rules that every seat on this machine reads, or does each project's rule file stay independent?

That is the whole question and it is the owner's, not ours. Nothing below needs
to be read to answer it.

## WHAT PROMPTED IT, measured 2026-09-15

Two seats, one machine, two working directories — `/home/neo/frank-user` and
`/home/neo/lekkerzeilen` — and therefore two rule files. The lekkerzeilen seat
independently rediscovered a rule that has been in this tree's `CLAUDE.md` at
line 672 for a fortnight:

> *editing a shell script that is currently RUNNING corrupts that run, because
> `/bin/sh` reads a script INCREMENTALLY, not into memory.*

They patched their bisect script in place while it was executing. The run
survived because the loop happened to be in memory — luck, not design — and the
recorded case here ended in `rc=2` on three shards, *"a shell parse error
wearing the shape of a verdict"*. **Same class, opposite outcome, and the
outcome is the random part.** The rule reached them only because it was quoted
in a peer message.

It is not one rule. The same evening produced three more that are about
MEASUREMENT and not about this compiler, and each was learnt twice:

| rule | learnt here | learnt there |
|---|---|---|
| a scan counts the observer | eight unexitable `pgrep` wait loops | `pkill -f` killing its own wrapper |
| an instrument can read the wrong quantity | fourteen RSS rows green on a use-after-free | an RSS ledger that cannot see a premature free |
| agreement is not corroboration | — | one sampler's rounding agreeing with itself across two runs |
| do not edit a running script | `rc=2` on three shards | the in-place `wpbisect.sh` patch |

## WHY NEITHER SEAT SHOULD JUST DO IT

The lekkerzeilen seat declined to copy the rule into their own file because a
peer told them to, and was right to: *"editing a CLAUDE.md because a peer told
me something belongs in it is exactly the thing I have to refuse."* This seat
will not move rules into a location the owner has not chosen either. Where the
rules live is configuration, and the direction of this change is "more places
load more rules", which is the owner's dial in both directions.

## THE COST OF EACH ANSWER, so the question is a yes/no and not an architecture

**Independent (today).** Every measurement lesson is learnt once per seat, and
the second learning is by accident. Four instances in one evening. The cost is
paid in wrong numbers, not in confusion — none of these rules announce
themselves when broken.

**Shared.** Every seat pays the shared file's tokens at startup, in a project
whose own rules file was cut from 72KB to rules-only *because every session paid
the history at startup*. A shared measurement file is a second startup cost on
every seat, including seats that never measure anything.

A third shape exists and is cheap: leave both files alone and let each seat's
own MEMORY carry the measurement rules, which is what the lekkerzeilen seat
did unprompted. It costs nothing at startup and it is per-seat, so it does not
survive a new seat.

**This ticket recommends nothing.** All three answers are defensible and the
one that is right depends on how many seats the owner intends to run, which is
his dial.
