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

## HOLDER-LIVENESS MEASURED, 2026-09-22 — 29 of 34 are held by seats that do not exist, and on today's population the CHEAP option separates them perfectly

*Added by `frankz-e5`, the coordinator, because "which seats exist" is the one
question this seat is placed to answer and the ticket's fork turns on it. The
census below is mine; the ticket, the 34-row population and the fork are
`frankb-8e`'s.*

**Population:** the 34 files in `devdocs/progress/working/`, at `837d3dc85`.
**Oracle for liveness:** `ListAgents` from this session, 2026-09-22 ~20:15 local
— eleven reachable sessions. **Oracle for staleness:** `git log -1 --format=%as`
on each ticket file.

**Live-held: 5.** `frankh-c0` (2), `frankb-8e` (2), `franks-5b` (1).
**Held by a name with no reachable session: 28.** **Owner field empty: 1.**

The 28 are held by `frankA` (8), `frankS` (7), `frankD` (2), `frankH` (3),
`frank-subcoord` (2), `franks-ab` (2), `frankB`, `frankC`, `frankZ`,
`frank-optimize`, `franka-29`, `frank-rust` (1 each). Most are the previous
naming generation, which is itself the tell: a `frank<letter>` with no `-<id>`
suffix has not been a live seat in this fleet for some time.

### THE RESULT THAT BEARS ON THE FORK, and it collapses most of its urgency

**All 5 live-held rows were last touched TODAY. All 28 dead-held rows were last
touched on or before 2026-09-20, and 27 of them on or before 2026-09-10.** So on
this population, *"last touched today"* separates live from dead **with zero
error in both directions.**

That is a calibration for option 1 and it says the cheap option is not merely
safe here, it is exact. **Option 2 is still the correct one** — the agreement is
a property of today's population, not of the mechanism — but the fork is no
longer *approximate versus correct*. It is *correct versus a proxy that is
currently perfect*, which is a much easier call and does not need a live query in
`ready`.

### Two ways this measurement could be wrong, and neither is hypothetical

1. **`ListAgents` answers "reachable from here, now".** A seat between restarts,
   on another host, or not accepting messages reads as dead. So *dead-held* means
   **no reachable session**, never *abandoned*. It is the right instrument for
   "should `ready` offer this", and the wrong one for "has this work stopped".
2. **A file's last-touch date is a LOWER BOUND on staleness** — `frankb-8e`'s own
   caveat and it cuts at my number too. A live seat can work a subsystem for days
   without editing the ticket, so the perfect separation above may be an artefact
   of all five live holders having claimed within the last few hours. **Re-run
   this on a day when nobody has just claimed before quoting the separation as a
   property of the proxy.**

### What is actionable TODAY without any tool change

CLAUDE.md already decides it: *`working/` is a status hint, not a lock; `owner:`
is ATTRIBUTION, not a claim* — and `check`'s own `STALE-PARK-HELD` text says to
consult `ListAgents` before treating an owner line as a lock, then take it. **The
28 are free to take now.** Nothing needs to land first. That does not close this
ticket, whose defect is that `ready` cannot SEE them; it means no seat has to
wait for the fix to work on one.

**Three rows where the cost is already concrete:**
`bug-t-pin-verify-builds-with-the-previous-pin-not-the-one-it-names` — **p80, the
highest number in the folder**, held by `frank-subcoord`, out of every queue
since 2026-09-06. `feature-pascal-corpus-oop` — p75, held by `frank-rust`, the
seat `check`'s OWN text cites as the worked example of a dead holder; **17 days
stale and still not offered to anyone.** `feature-pascal-corpus-expansion` — p75,
`frankD`, 2026-09-06.

**And the reason this is a coordinator's row rather than a tools row:** a
held-and-forgotten ticket is indistinguishable from a held-and-live one from
outside. That is *a pane is not a session* with a folder in place of a pane, and
the discriminator is the same one — ask the roster, not the artefact.

### TWO CORRECTIONS TO THE CENSUS ABOVE, from `frankb-8e`, and both weaken it in ways I understated

**1. THE SEPARATION IS CONTAMINATED BY THE DAY I MEASURED ON.** I wrote that the
perfect live/dead split "may be an artefact of all five live holders having
claimed within hours". It is worse than *may*. Four of the five live rows are
last-touched today **because a seat claimed today**, and one of them `8e` claimed
about twenty minutes before I ran the census. **So the live arm of my measurement
is partly a record of the fact that I measured on a claiming day** — an earlier
step of the day supplied what the live arm needed, which is the
measurement-creates-the-condition shape.

Scope of the damage, stated precisely because it is not total: **the dead-held 28
are untouched** — nothing anyone did that day could make a dead seat look dead —
so the census stands. **Only the SEPARATION is contaminated**, and that is the
part the fork was leaning on. **Nobody may quote "last touched today" as a
calibration for option 1 until it is re-run on a morning when nobody has just
claimed.**

**2. MY TWO SIGNALS ARE ONE SIGNAL.** I offered the `frank<letter>`-with-no-suffix
naming pattern as a corroborating tell beside the `ListAgents` result. It is not
corroboration: a seat from the previous naming generation is **both unreachable
and old**, so the two agree *by construction*. CLAUDE.md is explicit that two
readings which can go wrong the same way are one reading, and this is that.

**The instrument that would fail differently is `tools/whose_commit.sh`** over the
checkouts: it answers where a commit was AUTHORED, from reflogs, and depends on
nothing being reachable now. **If T builds option 2, that is the instrument to
point it at — not `ListAgents` inside `ready`**, which would make the ranker
depend on a live query that can fail, and which CLAUDE.md already warns about on
the process-scan axis.

*Both corrections are `frankb-8e`'s. The census they correct is `frankz-e5`'s.*

## FINAL CENSUS AT THE SHRINK, 2026-09-22 ~22:00 — the five rows that are about to join the invisible set, by name

*Run by `frankz-e5` as its last act, because the owner's directive (slow down,
finish current work, then ONE seat on ESP32) converts this ticket from a
standing defect into a **dated** one. Recorded so the single seat has the list
rather than the number.*

**Population:** `devdocs/progress/working/*.md` — **36** files, up from the 34
counted earlier the same day. **Liveness oracle:** `ListAgents`, ten reachable
peer sessions. **NO separation claim is made this time** — the earlier
"last touched today separates live from dead with zero error" was contaminated by
having been measured on a claiming day, and nothing here re-establishes it.

### The five currently live-held rows — THESE ARE THE ONES THAT MATTER

| owner | last touch (file) | slug |
| --- | --- | --- |
| `frankb-8e` | 21:57 | `feature-a-unreferenced-class-rtti-keeps-every-method-alive` |
| `frankb-8e` | **07:52** | `feature-a-object-output-for-arm32-and-aarch64` |
| `frankh-c0` | 21:38 | `decide-n-what-does-dunder-file-mean-for-a-module-inside-a-package` |
| `frankh-c0` | 20:07 | `feature-n-a-non-allocating-restricted-thunk-for-an-isr` |
| `franks-5b` | 16:16 | `perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program` |

**All three holders were asked to put each ticket's STATE INTO ITS SUMMARY before
stopping**, because a body that records its own state is the evidence nobody
reaches, and `working/` is in no ranked queue. Whether they did is checkable from
the summaries themselves and is not asserted here.

**The 07:52 row is the one to look at first.** It is the only live-held row not
touched in the evening, so it is the likeliest to have been left mid-thought.

### The other 31

Held by fifteen distinct owner names of which twelve have **no reachable
session**: `frankA`, `frankS`, `frankH`, `frankD`, `frankB`, `frankC`, `frankZ`,
`frank-subcoord`, `franks-ab`, `frank-optimize`, `franka-29`, `frank-rust` — plus
one row with an empty `owner:`. Unchanged in substance from the census above:
**CLAUDE.md says `owner:` is ATTRIBUTION, not a claim, so all of them are free to
take.** The named casualties there remain
`bug-t-pin-verify-builds-with-the-previous-pin-not-the-one-it-names` (p80, out of
every queue since 2026-09-06) and `feature-pascal-corpus-oop` (p75, held by
`frank-rust`, which `check` itself cites as its worked example of a dead holder).

### What this adds to the ticket

Nothing about the mechanism, which is unchanged. It adds **the dated list**: at
the moment the fleet shrank, these five rows were current work in flight, and
after it they are indistinguishable from the thirty-one. **A single seat reading
`ready` will see none of the thirty-six.** That is the whole cost of this ticket,
stated once with names attached.
