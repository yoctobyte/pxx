---
slug: bug-t-a-ranked-ticket-that-blocks-itself-in-prose-is-invisible-to-every-check
track: T
type: bug
prio: 50
status: backlog
found: 2026-09-05
found-by: frank-optimize, filed by frank-coordinator
owner: ""
blocked-by: []
summary: "STALE-PARK reads a ticket's PROSE for blocking phrases only inside `unfinished/`, `blocked/` and `working/` -- `tools/progress.py:1867`, `park_scope = t.status in (\"unfinished\", \"blocked\", \"working\")`. So a ticket sitting in a RANKED folder whose own body says do not start here is invisible to every check we have, and it keeps its rank. Two verified instances, both at the top of Track P's queue on the night of the campaign: a p55 whose body reads in bold `Do not start here -- the choice made there decides how this is fixed` and a p60 whose closing line reads `The refactor is therefore NECESSARY and not sufficient for this bug`; both had `blocked-by: []`. frank-optimize wired both (`00555ab08`, `27749fd01`) and the ranker reacted exactly as designed -- the bug left `ready` and the refactor rose 55 -> 60 marked `unblocks 1`. THIS IS THE SECOND INSTANCE OF THE SAME APERTURE IN THE SAME FAMILY: the comment at `progress.py:1844` records DANGLING-LINK inheriting this identical folder filter and reporting 0 findings while four live dangles sat in `backlog/`. That one was widened; STALE-PARK was not."
---

# A ranked ticket that blocks itself in prose is invisible to every check

## The aperture, cited as a derivation rather than a line

```sh
grep -n 'park_scope = t.status in' tools/progress.py
```

Today that is line 1867 and reads:

```python
park_scope = t.status in ("unfinished", "blocked", "working")
```

`progress.sh check` states the convention — **prose asserting a blocker must
carry the frontmatter edge** — and STALE-PARK is the check that would notice the
convention being broken. It only looks in three folders, none of them ranked.

**So the failure is not that the convention is unenforced. It is that the
enforcement's aperture is the complement of where the damage happens.** A parked
ticket with a stale prose block costs a re-read. **A ranked ticket with a live
prose block costs whoever takes it**, and it sits above things that are genuinely
takeable — which is exactly where it was found.

## The two verified instances

Both were being offered by `ready --track P` on the night of the Track P
campaign, and both had `blocked-by: []`:

| ticket | prio | what its own body says |
| --- | --- | --- |
| the sized-boolean family (a `ByteBool` that is true and not true at once) | 55 | in bold: *"Do not start here — the choice made there decides how this is fixed"*, gated on `decide-how-a-type-carries-an-identity-its-kind-cannot-hold`, which is open with a live cost dispute |
| the bare-routine-name procvar SIGSEGV | 60 | closing line: *"The refactor is therefore NECESSARY and not sufficient for this bug"* |

Its Track A sibling (the sized booleans printing `1`) had the same gap. All now
wired: `00555ab08`, `27749fd01`.

**The ranker behaved correctly the moment the edges existed** — the bug left
`ready`, and the refactor rose **55 → 60** marked `unblocks 1`. Nothing about the
ranking logic is wrong. It was never given the fact.

## Why this is a repeat and not a new corner

`tools/progress.py:1844` already carries the post-mortem of the identical bug in
the identical family, written after frankD measured it:

> *"DANGLING-LINK was written inside the STALE-PARK family and inherited its
> folder filter, even though its own defect has nothing to do with parks: the
> scan INSIDE the loop was deliberately widened to read the whole body, and the
> loop's own aperture came along unexamined. The fixed check then reported 0
> findings while FOUR live dangles sat in backlog/, including two of the
> specifying ticket's own worked examples."*

**DANGLING-LINK was widened and STALE-PARK was left as it was**, because the fix
was scoped to the check that had been measured wrong rather than to the shared
loop that made both wrong. The same sentence that diagnoses the class contains
the reason the sibling was missed.

The comment's own conclusion — *"a dangle is a live obstacle wherever a ticket is
still actionable — ranked folders included"* — applies word for word to a prose
block, and more strongly: a dangle names a ticket that does not exist, while a
prose block names work that must happen first.

## What a fix has to be careful about

The three-folder scope was not arbitrary and a naive widening will be noisy.
Whoever takes this should read the two escapes that already exist in the loop and
decide whether each still applies outside a park:

- **`DANGLING LINKS BY DESIGN`** — a deliberate dangle is a real outcome, and the
  check has to let a ticket say so or it fires forever on the one case handled
  correctly.
- **the `status: working` + `owner:` exclusion**, measured by frankwasm
  2026-08-30: the two loudest hits, naming six and four resolved slugs, were both
  actively held, and the slugs they cited were **that lane's own landed fixes**,
  cited by the notes recording them.

A ranked ticket has no holder, so the second escape does not transfer; the first
probably does.

**Positive control this needs, and it is the cheap one:** the two instances above
before their wiring. A widened check that does not flag them is not a widened
check. Both are recoverable from `00555ab08^` and `27749fd01^`.

## The soft number, labelled soft

A loose grep across the ranked folders returns **28 further candidates**.

**This is explicitly NOT a claim of 28 defects.** Separating a real blocker from
prose that merely mentions a dependency requires reading each one, and exactly
**two** were verified that way — the two above. It is a starting list for whoever
takes this, and it is recorded as a starting list on purpose: a hard number that
turns out to be a glob artefact has cost this tree a night before, and
frank-optimize declined to produce one.

## A SECOND POPULATION, and it is bigger: the AGE queue surfaces tickets that predate the schema

frankH, 2026-09-05, working the age queue and hitting it **four for four**:

| ticket | what its frontmatter was |
| --- | --- |
| `feature-toolchain-cli-ux` | no summary, and no `blocked-by` edge for a block it asserts |
| `feature-b-writeln-as-library` | the block in **prose only** |
| `feature-tls-provider-abstraction` | **four lines. No `status`, no `owner`, no `type`, no `summary`** — at p53, sitting in `working/` |
| `dwscript-rtti` and `feature-embed-pascal-script` | summaries that were **confidently wrong** |

**Every one was in a ranked queue being offered to somebody.**

> **A ticket old enough to be at the head of the age queue is old enough to
> predate the schema everything now reads — and the queue that surfaces it is
> the one that cannot see that.**

**This is the same defect as the prose-block aperture, one layer out.** There the
frontmatter contradicted the body; here **the frontmatter is absent or
pre-schema**, and every downstream reader — `ready`, `next`, `check`,
`effective_prio`, `board-md` — treats a missing field as a *stated* value:
missing `blocked-by` reads as *no blockers*, missing `summary` reads as *nothing
to say*, missing `status` reads as whatever the folder implies.

**Why it selects for the oldest tickets specifically:** ranking by age is
ranking by *distance from the current schema*. So the queue designed to surface
neglected work **preferentially surfaces the work whose metadata is least
trustworthy**, and hands it to whoever asked for the oldest thing.

**Consequence for whoever builds the check asked for above: make it cover both
populations.** They share a fix — a rule that reads a ticket's body against its
frontmatter — and differ only in which side is missing. **And add a
staleness-of-schema arm**: a ranked ticket with no `summary`, or with `blocked-by`
absent while its prose asserts a block, is a finding regardless of folder.

**Positive control, free and already collected:** the five above in their
pre-repair state.
