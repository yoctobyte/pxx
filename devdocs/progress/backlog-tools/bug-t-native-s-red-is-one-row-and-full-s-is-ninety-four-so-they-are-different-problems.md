---
slug: bug-t-native-s-red-is-one-row-and-full-s-is-ninety-four-so-they-are-different-problems
track: T
prio: 70
type: bug
status: backlog-tools
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "`umbrella-one-full-tier-run-with-no-red-tier` closed 2026-09-07 saying in its own last line `If it regresses, that is a new ticket`. IT HAS: measured at pinned ref `ad275f0d96c3` over all 2898 tstate reports in the tree, the last `full` GREEN is 2026-09-09T08:21:39Z and the last `native` GREEN is 2026-09-11T16:28:30Z. THE USEFUL FINDING IS NOT THAT BOTH ARE RED -- IT IS THAT THEY ARE RED IN COMPLETELY DIFFERENT SHAPES, which no aggregate verdict can say and which decides how much work `full green expected` actually is. NATIVE IS ESSENTIALLY ONE ROW: 14 distinct rows ever red in 306 RED reports since its last green, median 1 row per report, and `test-core#src:test/c_crtl_wait.c` is red in 306 of 306; clearing that one row alone would have made 51% of those reports GREEN, and eight rows reaches 96%. FULL IS BROAD: 94 distinct rows over 313 RED reports, median 6 per report, and the best eight rows together reach only 37% -- a long tail, not a few chronic blockers. So native is a finishing job and full is not, and quoting one tier's difficulty for the other is the error this ticket exists to prevent. Every one of the top rows ALREADY HAS AN OPEN TICKET (c_crtl_wait, crtl_reachability, threadsafe_heap_lock_deadlock_diag, crtl_atexit, compiler_srchash), so this state is UN-FINISHED, not un-triaged, and the fix is not more filing. WHAT WOULD RETIRE THIS TICKET: a `full` report with verdict GREEN at any sha after 2026-09-09. WHAT WOULD RETIRE ITS NUMBERS: any re-run at a different pinned ref -- carry both rows rather than replacing, since a count whose ref was not recorded is unquotable rather than refuted."
---

# `native` and `full` are both never-green, and that is where the resemblance ends

## Population, stated, because a bare count is not re-derivable

- **Pinned ref `ad275f0d96c39784d92a3159b74f686159cc3390`** (2026-09-22 02:34).
  Every number below is against that sha, and the reports were read **from the
  pinned tree** (`git cat-file`), not from a working copy — this checkout was
  at `a9af520b2` at the time, five reports behind, so reading from disk would
  have been a different population.
- **2898 reports**, every `devdocs/progress/tstate/reports/*` at that sha, all
  tiers, all hosts. Parse asserts `docs == files` before counting anything.
- **Oracle:** each report's own YAML `tier`/`verdict` and its `## STILL-RED`
  section. No inference from commit subjects.

## The tier verdicts, and a second count carried rather than replaced

Newest 1500 commit subjects at the pin, tier taken from a **whitelist** of tier
names — `bench … RED (0 bench rows, 550 conf)` otherwise parses as a tier, and
`<tier> <sha> done` is a completion rather than a verdict:

| tier | GREEN | RED | frankuser, 01:40, unpinned |
| --- | --- | --- | --- |
| native | 0 | 166 | 0 / 165 |
| full | 0 | 103 | 0 / 102 |
| opt | 6 | 14 | 7 / 14 |
| slow | 27 | 2 | 28 / 2 |

Both counts agree on the only thing that matters and differ by ±1 per tier,
consistent with a window that moved between 01:40 and 02:34. **Neither refutes
the other; they measured different windows, and only one of them recorded its
ref.**

## "NEVER GREEN" IS A PROPERTY OF THE WINDOW, NOT OF THE TIER

Over all 2898 reports, `native` has **175** GREENs and `full` has **57**. They
are not tiers that cannot go green — they are tiers that **stopped**:

| tier | reports | GREEN | last GREEN |
| --- | --- | --- | --- |
| native | 1550 | 175 | 2026-09-11T16:28:30Z |
| full | 1188 | 57 | 2026-09-09T08:21:39Z |
| opt | 139 | 7 | 2026-09-16T17:43:25Z |
| slow | 17 | 5 | 2026-09-19T17:19:56Z |

That is worth more than the zero: it gives a **bounded bisect window** for each
tier instead of an open-ended one.

## THE ROWS — and this is the question an aggregate cannot answer

Counting distinct `## STILL-RED` rows in the RED reports **since each tier's own
last green**:

| | native | full |
| --- | --- | --- |
| RED reports in span | 306 | 313 |
| distinct rows ever red | **14** | **94** |
| rows per report (min/med/max) | 1 / **1** / 5 | 0 / **6** / 20 |
| rows red in ≥50% of reports | 1 | 4 |
| rows red in exactly one report | 1 | 34 |

**`test-core#src:test/c_crtl_wait.c` is red in 306 of 306 native reports.**

Greedy — clear the row that unblocks the most reports, then repeat:

    native                                        full
    1 row  -> 51% green                           1 row  ->  3% green
    2 rows -> 72%                                 4 rows -> 13%
    4 rows -> 79%                                 6 rows -> 20%
    8 rows -> 96%                                 8 rows -> 37%

**So they are different problems wearing one verdict.** `native` is a finishing
job — one test fixed makes half its runs green. `full` is a long tail where the
eight best rows leave 63% still red. Any plan, estimate or release claim that
treats "both tiers are never green" as one fact is wrong by roughly an order of
magnitude on one of the two, and which one depends on the direction you guessed.

## This is UN-FINISHED, not un-triaged

Every top row already has an open ticket — `c_crtl_wait` (4 open), `crtl_reachability`
(5), `test_threadsafe_heap_lock_deadlock_diag` (3), `crtl_atexit` (2),
`compiler_srchash` (6). **The gap is not filing and this ticket must not become
more of it.** What is missing is that nobody had the row count, so nobody could
see that native is one fix from half-green while full is not.

## Wiring

Feeds `umbrella-a-stranger-can-get-a-working-compiler-from-a-release` (p80),
whose `blocked-by` already names `umbrella-one-full-tier-run-with-no-red-tier` —
now in `done/`, closed 2026-09-07 **by a run rather than a decision**, with
`If it regresses, that is a new ticket` as its own last line. This is that
ticket. The closed umbrella is **not** reopened: it recorded a real event, and
a terminal ticket that stays true about the past is working correctly.

## Not established, and named so nobody assumes it

- **Whether the rows are the same FAILURE each time**, only that the same job id
  is red. A job id red for eleven days could be one cause or several.
- **Flakiness is not separated out.** Reports carry a `flaky` field that this
  census does not read; a row red in 1 of 313 reports may be noise rather than a
  defect, which is most of the 34 one-offs.
- **`opt` and `slow` are not characterised here** — they do go green and are not
  on the critical path for this claim.
