---
slug: bug-the-queue-makes-filing-a-duplicate-the-path-of-least-resistance
track: A
prio: 70
status: done
owner: opus5-frank1
---

# The queue makes filing a duplicate the path of least resistance

## The evidence, which is a measurement and not a worry

`feature-t-gate-quick-should-smoke-the-pinned-compiler` and
`bug-t-gate-quick-cannot-see-a-broken-pinned-rtl` are **the same defect filed
twice**, four days apart, both at `prio: 65`, by two different agents, from two
genuinely different incidents (`PXXVariantErrorHook` and `PXXNilRefHook`).
Neither cites the other. Both are now closed by one change (`1cc54252e`).

Nobody detected the duplication for four days. It surfaced only because
`tools/progress.sh next --track T` happened to hand one agent the second ticket
immediately after it closed the first. Had the ranking put anything between
them, both would still be open, and a third incident would have produced a third.

## Why this is a triage bug and not a tidiness bug

The project owner's loudest standing complaint is that **triage is the
bottleneck** -- *"I see low-prio tickets that I would rank highest. And vice
versa."* A queue in which filing a duplicate is the cheapest available action
manufactures its own backlog, and does it in the way that damages ranking most:
one real problem appears as N items of middling priority rather than one item of
high priority. Two independent rediscoveries in four days is evidence a seam
matters; split across two tickets, it read as two ordinary 65s.

Note the failure is not that the filers were careless. Each did the right thing
from a real incident. **Nothing in the workflow would have told either of them
the other ticket existed** -- `next` and `ready` rank, they do not search, and a
filer with a fresh incident has no reason to grep the backlog for a symptom
described in someone else's words.

## What to look at

- A `progress.sh` path that runs *at file time* over open ticket titles/bodies
  and surfaces near-neighbours -- the cost is one prompt to the filer, and the
  filer is the only person holding enough context to judge the match.
- Whether `resolve` should ask the same question in reverse: this change closed a
  ticket, does it also close any of these?
- Duplicate pairs that already exist in the backlog. This one was found by luck;
  it should not be the only one.

Deliberately not proposed here: any scheme that ranks or auto-merges without a
human-or-agent judgement in the loop. The point is to make the existing
information *reachable at the moment of filing*, not to guess.

## Provenance

Found by the Track T agent while closing both tickets in one change, 2026-08-26.
Filed by the coordinator; T was told not to spend cycles on it.

## Outcome

All three "what to look at" items are built, in `tools/progress.py`.

**`progress.sh near "<text>"`** — the at-file-time path. Prints the closest OPEN
tickets to a candidate title with a percentage, the track, the prio, the folder
and the head of the body. It answers the exact question the two T filers could
not have answered: *has someone already described this in their own words?* On
the query *"a method call does not type-check its arguments"* it surfaces
`bug-p-a-single-candidate-method-call-does-not-check-its-argument-types` at 35%
— a ticket filed hours earlier in this session, whose title shares one content
word with the query.

**`progress.sh resolve`** — the reverse question, automatic. After a ticket moves
to `done/` it prints that ticket's near-neighbours, so a fix that covers more
than its own ticket says so at the moment the evidence is freshest. Wrapped in a
try/except: the advisory must never be able to fail a resolve.

**`progress.sh dupes`** — the retrospective scan. Every open pair, scored,
above a floor. It earned its keep on the first run: three watcher-filed
`regression-*` stubs at 82%, 64% and 62%, all for defects already fixed. I
verified each repro green and closed them — `backlog` went 265 → 262 before this
ticket was even finished.

### The metric was chosen by measurement, not by taste

The known-duplicate pair from the evidence section is the calibration point, and
the first two metrics both failed it in opposite directions:

| metric | known dup | median open pair | failure |
| --- | --- | --- | --- |
| Jaccard | 0.179 | 0.039 | a 6-word title scores <0.03 against everything — `near` is useless for the case it exists for |
| containment | 0.86 | — | `feature-dwarf-debug-info` scores 0.86 against a Variant-shift title; long tickets swallow short queries |
| **IDF cosine** | **0.350** | **0.078** | — |

IDF weighting is what makes the difference: every ticket says *pxx*, *compiler*,
*test*, *fix*; almost none say *dynarray* or *variant*. Cosine's
`inter / sqrt(w(a)·w(b))` normalisation is what stops a long ticket from
dominating the way containment did.

The second correction was **comparing like with like**. `near` takes a title and
so scores it against ticket *heads*; `dupes` has two full tickets and scores
whole bodies. Scoring a title against a body was the containment failure wearing
a different metric.

### Guard

`tools/progress_near_devtest.py`, 7 checks, already gated — `tools-devtest`
globs `tools/*devtest*.py`, so no Makefile edit was needed. It pins the
calibration *properties*, not the numbers: a known duplicate outscores the median
open pair by ≥2×, a ticket's own title ranks it first, a short unrelated query
does not saturate against the longest ticket, self-similarity is 1, symmetry, an
empty query scores 0. Numbers drift as the board changes; those properties are
what "the ranking is meaningful" actually means.

Check 1 asserts the known duplicate pair is still *loaded* — the calibration
point is two `done/` tickets, and `Board()` loads every folder, so it does not
age out. It is a hard check on purpose: if those two files ever disappear, the
rest of the devtest is measuring against a reference it no longer has.

### Documented

`devdocs/progress/README.md` gained a **"Before you file: `near`"** section next
to the `backlog_new/` rationale, and `near` is in the self-serve loop block.
Filing is still free and still uncontrolled — tickets are markdown written
straight into `backlog_new/`, so there is no `file` subcommand to hang a prompt
off. This is a habit the docs teach, not a gate. Making it a gate would need a
`file` subcommand, which is a bigger change than the evidence supports.

### Deliberately not done

No auto-merge, no auto-close, no re-ranking — as the ticket asked. Every output
says a match is a question, not a verdict. `dupes`' loudest non-duplicate is a
`decide-*` ticket beside the `feature-*` that implements it (49%, 44%, 44% in
the top five); that is correct behaviour and is documented as such rather than
tuned away.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
