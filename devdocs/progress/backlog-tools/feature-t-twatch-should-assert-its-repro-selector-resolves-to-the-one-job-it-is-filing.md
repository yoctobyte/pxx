---
prio: 55
track: T
---

# feature(T): twatch should assert its `## Repro` selector resolves to exactly the job it is filing

The actionable half of
`decide-a-repro-line-in-a-ticket-is-not-a-command-anyone-has-run` (Track U,
`9b44d6808`, sharpened by frankh-15 at `0e87df33d`). The prose ask was
**withdrawn**; this is the part that survived it, and it does not need the owner.

## The class, in its corrected form

Not *"a ticket contains a command nobody ran"* — twatch DID run the job; that is
how it knows the job is red. What was never executed is the **command string**,
which is a *reconstruction* of an execution that really happened. frankh-15's
correction of its own word, and it is the sharper statement:

> **An artefact that RECONSTRUCTS an action rather than recording it can diverge
> from the action silently, because the reconstruction is assembled from parts
> that were each individually correct.**

That is why nothing errored: the tier was right, the job id was right, the quoting
was right, and the string still named something the repo would refuse to run.

## Do the verify, NOT the label

Two options were on the table and they are **not equally good**. Drop the
labelling one — a caveat printed on every auto-filed ticket is read once and
never again, and this repo measured the sharper form of that the day before:
frankc-af's own retraction, where hedging the conclusion made an unmeasured
number read as the checked part. **A blanket "this may not work" on the artefact
every agent starts from is that same shape**, and it would make the confident
half more credible, not less.

## The mechanism, measured

`tools/testmgr.py --list` (`testmgr.py:5591`, *"print job table and exit"*;
`:5726` confirms it does no work) resolves a `--job` selector without running
anything, and **fails in both directions that matter** — measured by frankh-15:

| selector | result |
| --- | --- |
| a literal job id | `total: 1 jobs`, rc=0 |
| a stale/renamed id | `no jobs match`, rc=1 |
| `test-core#*` | `total: 1867 jobs`, rc=0 |

So at filing time twatch can assert that the string it is about to print selects
**exactly one** job — not zero, not 1867 — at no measurable cost. That is a
positive control in this repo's sense: drawn from the right population and able
to come out false.

## Where to do it, and the trap in it

Three sites emit a repro: `twatch.py:2085`, `:4286`, `:4441`.

**`:4286` is a TEMPLATE with a literal `'<job>'` placeholder** (*"start with a
suspect, or any listed job"*), written for a human to fill in. It must NOT be
asserted against — a naive "exactly 1" check across all three sites fails there
forever, and the likely reaction is to weaken the assert for all of them rather
than exempt the one. Exempt the placeholder site explicitly and keep the other
two strict.

## Why this is worth doing even though the hook is fixed

`448b21c11` means today's instance cannot recur. But this instance was caught
**because the refusal was LOUD**, not because anyone checked. A reconstruction
that RUNS and selects the WRONG job — a stale id after a rename, a glob that
widened — hands the next agent a confident wrong answer with nothing to
disbelieve. That is the failure mode with no alarm on it, and it is the one the
assert actually buys.

The literal-versus-glob boundary here is the same one `448b21c11` drew in the
hook aperture. Two mechanisms landing on the same distinction independently is
mild evidence it is a real boundary rather than a convenient one.

## Gate

Track T's own. It touches `tools/twatch.py` only, runs no suite, and wants one
test row per emitting site — including a red row for the stale-selector case,
which is the direction that has no other alarm.
