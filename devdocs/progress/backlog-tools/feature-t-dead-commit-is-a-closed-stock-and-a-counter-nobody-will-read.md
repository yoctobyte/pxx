---
track: T
prio: 30
type: feature
status: open
found: 2026-08-30
found-by: claude-T
---

# The 350 dead citations are unrecoverable and finished; the risk is now the counter

Measured at `origin/master`, 2026-08-30, because nobody had established whether
that number was mostly recoverable or mostly gone.

## The population, with its definition attached

**350 `WARN-DEAD-COMMIT` lines, 269 distinct shas.** Classified by whether the
object exists in this checkout and whether it is an ancestor of `origin/master`:

| | count | share |
| --- | --- | --- |
| object absent entirely — **genuinely gone** | **264** | 98.1% |
| object present but unreachable (dangling) | 5 | 1.9% |
| ancestor of `origin/master` — false positive | **0** | 0% |

**The check has no false positives.** Every sha it flags is genuinely not on
`origin/master`.

> Careful with the two numbers: 350 is *citations*, 269 is *distinct shas*.
> Same trap as the face-count reconciliation the same evening — they are two
> populations, and quoting one as the other is how this kind of measurement goes
> wrong.

## `patch-id --stable` cannot recover any of them, and this is structural

The open question was whether the stock could be repaired by matching patches
across a rebase. It cannot, and not for a statistical reason:

> **Computing a patch-id requires having the object.** For all 264 the object is
> absent from the repository. There is nothing to compute a patch-id *of*.

The 5 dangling ones could be recovered — but only in **this** checkout, only
until the next `gc`, and they are all `fix(T):` commits from one lane's reflog.
That is not a recovery route anyone else can take; it is precisely the case the
`_audit_citations` docstring already names as why `origin/master` is the oracle
rather than the local object DB.

The only remaining route for a dead sha is a human matching the ticket's prose
against master's history by date and content. Per-ticket, manual, and worth it
only where a specific citation is actually being chased.

## It is a CLOSED stock, not a leak — and that is the actionable half

By the date on the citing line:

| month | dead citations |
| --- | --- |
| 2026-06 | 10 |
| 2026-07 | **260** |
| 2026-08 | 31 — and **all on or before 2026-08-08** |

**Zero in the 22 days since.** `68be6bd59` (2026-08-03) taught resolve/sync to
cite the sha a resolve *landed* as rather than the one the rebase eats; the
citations stop within days of it, with a four-line tail on 08-08. Correlation,
stated as such — but the mechanism is known and the tail is consistent with it.

## The risk is no longer the citations. It is the number.

350 is permanent, unrepairable, and will now sit there forever.

> **A counter that never changes stops being read, and then a 351st is
> invisible.** The stock is harmless; a new dead citation would not be, because
> it means the resolve/sync path has regressed — and it would arrive as
> `351` where `350` used to be.

That is the same failure this repo has hit twice recently: a denominator that
always equals its numerator, and a proxy whose discriminating power decayed to
nothing while its output kept the same shape.

**Proposal:** split the count at the date the leak closed.

- report pre-`2026-08-09` dead citations as a single frozen line — *"legacy: 350
  citations, 269 shas, unrecoverable, closed 2026-08-08"* — that does not move;
- report post-threshold ones **individually and loudly**, because one of those
  is a live regression in the resolve/sync path;
- **state the threshold as a dated claim in the same commit** (face 232b), since
  it is exactly the kind of literal that gets copied into the next check and
  never re-examined.

Do NOT repair or delete the 350 citations themselves. They are honest records of
what a session actually cited, and rewriting them would falsify history for no
recovered information — the same rule that protects handoff notes and `done/`
write-ups.

Gate: `tools/progress.sh check` still reports the same underlying set; the
frozen line and the live line must sum to it, and a deliberately-planted recent
dead sha must appear in the live line and not be absorbed by the frozen one.

## Why "clean these up later" was never an available option (2026-08-30)

Added after frankB and the coordinator measured the locality of the checks
(faces 235d / 235d-control / 235e).

A dead citation has two possible histories — **a real sha a rebase superseded**,
or **a sha that never existed** — and they are distinguishable **only in the
checkout that wrote it, while its reflog still holds the object**. Measured:
frankB's five own rebased-away shas all resolve in its tree; the invented one
does not. Measured from `~/frank-coordinator`, **all** of them answer
`NO SUCH OBJECT`, including the two that were real.

So the classification is not merely expensive later — **it is impossible later**,
and impossible for every reader other than the author. `patch-id --stable` cannot
substitute, because computing a patch-id requires having the object, and 264 of
the 269 distinct shas are absent entirely.

**Consequence for this ticket, and it is the operational one:** the value of the
counter is not in eventually resolving the 350. Nothing will ever resolve them.
It is in catching the **351st on the day it appears**, while the tree that
produced it still exists — which is exactly what a number that never moves stops
doing. Split at the date the leak closed (`68be6bd59`) so the live count starts
at zero and any increment is visible.

**And it is an argument about writing, not about cleanup:** draw the distinction
in the ticket *at the moment of citing*, because the reader will have strictly
less information than the writer did, permanently.
