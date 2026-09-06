---
slug: bug-t-stale-park-is-dominated-by-wall-ladder-tickets-that-can-never-stop-firing
track: T
prio: 35
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "`progress.sh check`'s STALE-PARK query is dominated by a ticket shape it can never clear: a WALL-LADDER whose body is a chronology of cleared blockers, so every rung adds prose naming a now-resolved ticket beside a blocking phrase and the hit count only GROWS as the ticket succeeds. Measured 2026-09-06 (frankD): `feature-pascal-corpus-expansion` alone produced 20 windows, and with `feature-pascal-corpus-generics` it was the ENTIRE STALE-PARK output for Track P -- so any real stale park in the lane sits behind two tickets that cannot stop firing. The existing escape, `PARK CONDITION SUPERSEDED`, excuses THAT BLOCK ONLY by design, which is right for an ordinary park and means a ladder needs one marker per rung forever. A check whose output is dominated by two permanent entries is as empty as one that never fires."
---

# The check's own success condition is what makes a wall-ladder fire

STALE-PARK looks for a resolved ticket's slug within +/-2 lines of a blocking phrase, in the
PROSE of a parked ticket. That is the right query for a park whose resume condition has quietly
been met.

**A wall-ladder ticket is the opposite shape and trips it by construction.** Its body is the
record of walls cleared in order — rung 1 blocked on X, X landed, rung 2 blocked on Y, Y landed
— so each rung permanently adds a resolved slug next to a blocking phrase. **The ticket firing
more is the ticket going better.**

## Measured

- `feature-pascal-corpus-expansion`: **20 windows**, alone.
- With `feature-pascal-corpus-generics`: **the entire STALE-PARK output for Track P.**

So the lane's real stale parks — the ones the check exists for — are invisible behind two rows
that will never go away and will grow.

## Why the existing escape does not answer it

`PARK CONDITION SUPERSEDED` excuses **that block only**, deliberately, so a new stale condition
added later still fires. That is correct for an ordinary park and is exactly what makes it
unusable here: a ladder needs a marker per rung, forever, added by whoever writes each rung,
and a missed one is indistinguishable from a real hit.

## The fork, which is why this is a ticket and not a fix

Any repair trades the check's own coverage against its signal, and the trade is a judgement
nobody should make on the way past:

- **A whole-ticket exemption** (`PARK LADDER` in the frontmatter or first block) is one line and
  it turns the check OFF for the ticket — including for a genuinely stale park added to it
  later, which is the case the check exists for.
- **Exempt a designated HISTORY region** — everything below a marked heading is chronology, not
  a live condition. Narrower, and it needs the region convention to exist and be used.
- **Require the blocking phrase to be in the PRESENT tense / not adjacent to a landed-marker
  phrase.** Most precise, most brittle, and it is prose parsing.
- **Report per-ticket rather than per-window** — cheap, does not reduce noise, but stops one
  ticket burying a lane's whole output. Possibly enough on its own, and it is the only option
  here that loses no coverage.

Recommendation, held weakly: the last one first, because it is the only one that costs no
coverage, and measure whether the lane's output is legible before spending anything on the
others.

## Measured after filing: the OTHER rows are real, which sharpens this ticket

2026-09-06, frankS, board-wide on the STALE-PARK output after `a39d93e7e`. **Of the 14 flagged
citations locatable as `[[wiki-links]]`, ZERO have resolution prose inside the check's own +/-2
window.** 6 of the 20 flagged citations have no wiki-link form, so the zero covers 14 of 20; the
run came after a Track P marking cleanup, so 22 markings were inside the sampled population
(two files against a board-wide run).

**Two consequences for this ticket, and they point the same way.**

1. The non-ladder rows are **live park conditions**, not stale ones — the check is accurate
   where it is not drowned. So the noise here has exactly one source, the ladders, and there is
   no second population to chase.
2. It **kills the other repair I might have reached for**: a companion sweep stamping
   already-fixed parks from before the convention existed. That cohort was predicted, measured,
   and is one instance repo-wide. Not a class. See `debugging-playbook.md`,
   `## A CHECKER KEYED TO A MARKER STRING`, corrected at `7ee2ed22d`.

This raises confidence in the weakly-held recommendation above: if the surviving rows are all
true positives, then per-ticket reporting is not merely the cheapest option — it is the only
problem left, because legibility is the whole defect.

## Not this ticket

The HELD branch's guidance (it told the reader "DO NOT CLAIM IT — tell the holder", which
contradicts CLAUDE.md and cannot be followed when the holder is a dead seat) was corrected in
place rather than filed — it was wrong rather than a trade-off.
