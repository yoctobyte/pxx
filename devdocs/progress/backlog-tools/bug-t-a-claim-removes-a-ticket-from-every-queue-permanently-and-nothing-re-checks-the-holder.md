---
prio: 55
track: T
summary: "`ready`/`next` never rank `working/`, on the premise that it is `a LIVE LOCK. An agent is on it right now` (tools/progress.py, RANKED_STATUSES comment). CLAUDE.md says the opposite in its own words -- `working/ is a status hint, not a lock; owner: is ATTRIBUTION, not a claim` -- and precedence says CLAUDE.md wins. NOTHING RE-CHECKS THE PREMISE, so `claim` is a permanent removal from every queue and a seat that ends its turn strands the ticket for good. MEASURED at e460f02a2, population `ls devdocs/progress/working/*.md` = 34, oracle `tools/progress.sh ready` with no --track, matched by slug: ZERO of the 34 appear. 33 carry an owner; by `git log -1 --format=%as` on the ticket file, 27 were last touched on or before 2026-09-10 and only 4 today -- so the premise is false for 27 of 34 and the folder is holding a p80, two p75s and a p70 that no dispatch can see, the oldest since 2026-08-31. Own prio UNDERSTATES the loss: the one row measured both ways (feature-a-unreferenced-class-rtti-keeps-every-method-alive) is own 30 and effective 70, and it became visible only because a seat happened to move it back by hand. THIS EXACT MECHANISM WAS ALREADY FOUND AND REPAIRED ONE FOLDER OVER: the same comment records `unfinished/ IS ranked (added 2026-08-25) ... Leaving it out hid 23 tickets from every dispatch, including the repo's highest prio (88, an N segfault)`. AND `check` ALREADY HAS THE APERTURE, SCOPED TO THE SMALLER HALF: UNOWNED-IN-WORKING fires on the 1 row with no owner and calls it `INVISIBLE IN BOTH DIRECTIONS`, treating the folder's silence as CORRECT for the other 33. THE FIX IS NOT `rank working/` -- 4 rows really are live and dispatching a second seat onto held files is the hazard the exclusion exists for. The fork is what evidence retires a claim, and it is a Track T design call, not a guess: see the two options in the body."
status: backlog
owner: unassigned
---

# A claim removes a ticket from every queue permanently, and nothing re-checks the holder

- **Type:** bug (dispatch correctness) — Track T
- **Status:** backlog — filed 2026-09-22 by frankb-8e (Track A), who hit it from the inside

## What

`Board.RANKED_STATUSES` in `tools/progress.py` omits `working/`. The comment
beside it gives the reason, and the reason is a claim about the world:

> `working/` — a LIVE LOCK. An agent is on it right now; ranking it would
> dispatch a second agent onto held files.

Nothing anywhere re-evaluates "right now". A seat that claims a ticket and then
ends its turn — the ordinary way a session stops, and CLAUDE.md's own
"a session that stopped short and a session that is stuck are the same
silence" — leaves the ticket outside every queue for as long as the file sits
there. The folder is write-once in practice.

## The measurement

Tree `e460f02a2`. Population: `ls devdocs/progress/working/*.md`, 34 files.
Oracle: `tools/progress.sh ready` (no `--track`), slugs matched with `grep -Ff`.

| | |
| --- | ---: |
| in `working/` | 34 |
| of those, appearing in `ready` | **0** |
| carrying an `owner:` | 33 |
| last touched on or before 2026-09-10 (`git log -1 --format=%as` on the file) | **27** |
| last touched today | 4 |
| oldest last touch | 2026-08-31 |

Stranded by own prio: `bug-t-pin-verify-builds-with-the-previous-pin-not-the-one-it-names`
p80 (2026-09-06), `feature-pascal-corpus-oop` p75 (2026-09-05),
`feature-pascal-corpus-expansion` p75 (2026-09-06),
`feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident` p70.

**Own prio understates the loss, so do not rank this ticket on the table above.**
`ready` prints EFFECTIVE prio, and the one row measured both ways —
`feature-a-unreferenced-class-rtti-keeps-every-method-alive`, moved out of
`working/` by hand at `e460f02a2` — is own 30 and effective **70**. The others
are unmeasured because the tool that would compute it is the tool that skips
them.

**What the file's last-touch date is NOT:** evidence about the holder. A live
seat can work a subsystem for days without editing the ticket. It is the
cheapest available proxy and it is a lower bound on staleness, not a census of
dead seats. `tools/whose_commit.sh` and `ListAgents` are the instruments that
answer the real question, and neither is wired into anything here.

## Why it survived

`check` already reasons about this folder being invisible, and scoped it to the
one row it cannot be wrong about. `UNOWNED-IN-WORKING` fires on the single
unowned ticket and calls that combination *"INVISIBLE IN BOTH DIRECTIONS"* —
but its stated reason for the invisibility is *"the folder tells `ready`/`next`
not to offer them"*, i.e. it treats the folder's silence as CORRECT and blames
only the empty `owner:`. The 33 owned rows are the same invisibility with an
attribution attached, and no aperture looks at them.

The identical mechanism was found and repaired one folder over, and the repair
is recorded in the very comment that excludes this one:

> `unfinished/` IS ranked (added 2026-08-25). ... Leaving it out hid 23 tickets
> from every dispatch, including the repo's highest prio (88, an N segfault)
> and the html5lib ladder at 65.

## The fork — Track T's call, not a guess

**"Just rank `working/`" is wrong**: 4 rows are genuinely live today, and
dispatching a second seat onto held files is the exact hazard the exclusion
exists for. The question is what EVIDENCE retires a claim.

1. **Rank it with an age threshold.** `working/` tickets older than N days by
   last file touch enter the ranked queue, flagged `(held by <owner>, stale
   Nd — message them first)`. Cheap, no new instrument, and wrong in the safe
   direction: it offers stale rows and never hides live ones. Picking N is the
   whole decision.
2. **Rank it on holder liveness.** `ListAgents` / a checkout scan says whether
   the owning seat exists at all. Correct rather than approximate, and it makes
   `ready` depend on a live query that can fail — and CLAUDE.md is explicit
   that a process-table scan counts the observer and that `trackt.py health`
   answers about the wrong machine.

A third, orthogonal and cheap either way: **widen `UNOWNED-IN-WORKING` into
`STALE-IN-WORKING`** so `check` at least reports the 27, which costs nothing
and does not change dispatch.

## Acceptance

Not "the number got smaller". **Every row `ready` newly offers must be one a
human agrees is not being worked**, and no row a live seat is holding may be
offered without the flag. Re-run the census above and state the population, the
tree and the oracle beside the new number — and say which rows moved because
somebody finished them rather than because the ranker changed.

## What would retire this ticket as filed

The premise going true: something that re-checks the holder. If `working/`
stays unranked and a liveness check lands elsewhere, this is still open — the
defect is that `claim` is irreversible from the queue's point of view, not that
the folder is unranked.
