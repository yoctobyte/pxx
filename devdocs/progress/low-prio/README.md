# `low-prio/` — real, not wrong, and not worth carrying in the ranker

**This is not `rejected/` and it is not `rainy-day/`.** The three say different
things and the distinction is the whole point of the folder:

- **`rejected/`** — the ticket is WRONG. The observable is unreachable, the
  premise is false, or matching the behaviour is not a goal.
- **`rainy-day/`** — real, intended, and a FUTURE PLAN. Big work or not directly
  language-relevant, deliberately deferred: extra CPU targets, OS ports, DWARF,
  allocator infra.
- **`low-prio/`** — real, probably correct, and **so far down the queue that
  carrying it costs more than it returns.** No plan to do it. No claim it is
  wrong.

## Why keep them at all

Two reasons, and neither is sentiment.

1. **So they are not refiled.** A finding that is deleted gets rediscovered and
   written up again by the next agent who trips over it. The record is cheaper
   than the rediscovery.
2. **So one can come back.** Priority is a judgement about now. A ticket here
   may become relevant when the thing it touches becomes load-bearing.

## Mechanics

Loaded but **never ranked** — `ready`/`next` read `RANKED_STATUSES` only, so
nothing here is ever dispatched. The board, `check`, and blocker resolution do
see it, which is why moving a ticket here does not dangle the links that cite it.

`status: low-prio`.

## Pulling one back

Move it to the owning lane's backlog, set `status: backlog`, and **say in the
ticket what changed** — what made it matter now. Restoring it because it looks
interesting is how the pile comes back.

## How this folder was created

2026-09-02, owner decision. 69 of 73 open `track: T` tickets were moved here in
one action: 73 of the 74 had been filed between 08-31 and 09-02, 58 on a single
day, and the pile was too large to work while returning almost nothing. Four were
kept in the ranker on a structural test — an active umbrella, or a hard
`blocked-by:` edge from live work.

The first cut put them in `rejected/`, which was wrong: it says the tickets were
mistaken, and they were not.
