---
slug: bug-t-pin-verify-and-requested-verify-publish-a-verdict-with-no-manifest
track: T
prio: 60
type: bug
status: backlog-tools
found: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "The two publish paths that most need a manifest are the only two that produce none. An ordinary breadth run prints `report=<path>` and writes a 17-key archive row carrying `still_red`, `skips`, `skip_holes`, `skip_hole_jobs`, `unreached` and `timed_out`. PIN-VERIFY (10-key rows, from ~2026-09-01, when pin-verify began running at `full`) and REQUESTED-VERIFY (9-key rows) print no report line at all and write a short row with none of those fields. NOT data loss and NOT a failed write — seven's daemon log shows no error, no truncation and no racing writer; the paths simply do not generate a report, by construction. The consequence is what matters: a `verdict: RED` with no `still_red` is unreadable — nobody can say WHAT was red — and a requested verify CLEARS THE REQUEST QUEUE while telling nobody the answer they asked for. Worse, the manifest EXISTS at the moment of publication and is dropped on the way to the archive: the same log line that publishes the verdict names `test-core#src:test/c_cross_...` and `tools-devtest#00`. 17 of 415 full rows are affected. DO NOT audit the 92 14-key rows — those are a clean schema cutover on 2026-08-31 and are healthy."
---

# Pin-verify and requested-verify publish a verdict with no manifest

## What the daemon log shows, and it is the whole finding

Every ordinary breadth run prints a report path. Neither special path does:

```
twatch: a8aa948df2f9 RED   report=…/20260906T181014Z-a8aa948-seven.md
twatch: 6a6d69ce2a80 RED   report=…/20260906T181507Z-6a6d69c-seven.md
twatch: dd742537ed52 GREEN report=…/20260906T181946Z-dd74253-seven.md

twatch: verifying PIN v406 (1b903c1ddaf2) at full          <- no report=
twatch: requested verdict RED at 5411e996794f (full)       <- no report=
```

No error, no truncation, no second writer. **Two deliberate paths do not
generate a report**, and the short archive row follows from that rather than
from anything going wrong.

## Which shape is which

| row shape | count | path | first seen |
| --- | --- | --- | --- |
| 17 keys | 306 | ordinary breadth | 2026-08-31 (current schema) |
| 14 keys | 92 | ordinary breadth, **older schema** | before 2026-08-31 |
| 10 keys | 7 | **pin-verify** | ~2026-09-01, when pin-verify began running at `full` |
| 9 keys | 10 | **requested verify** | 2026-08-29 |

**The 14-key rows are a clean cutover and are not a defect.** Every one predates
2026-08-31T05:23Z and every 17-key row postdates it, with no interleaving. They
are listed here only so nobody audits 92 healthy rows — the anomaly is 17, not
109.

The 10-key shape being *newer* than the 17-key one is what killed the obvious
hypothesis ("an old writer still in the tree"). It tracks when pin-verify
started running at `full`, not a regression.

## The fields that go missing

Present in a normal row, absent from both short shapes:

```
still_red   skips   skip_holes   skip_hole_jobs
unreached   timed_out   deadline   code_fp   first_seen
```

## Why this is worth fixing rather than documenting

**The two paths that most need a manifest are precisely the two that produce
none.**

- A **pin-verify** verdict with no skip/red manifest is exactly what a *graded*
  pin is supposed to carry. CLAUDE.md's rule is that a pin is graded — `green`,
  or `reds(N)` **with the manifest**, recorded at pin time. This path publishes
  the grade and drops the manifest.
- A **requested** verify is by definition the case where a human asked and
  wants the answer. It satisfies the request, clears the queue, and answers
  nothing. Measured consequence: `1d8db8667267` was reported to the fleet as
  *satisfied, not pending* — correct about the queue, and the evidence
  satisfying it was a thin row.

## The information already exists — it is dropped in transit

This is the part that makes it small. The publishing log line **already names
the failing jobs**: `test-core#src:test/c_cross_…` and `tools-devtest#00` for
the 19:32:19Z run. So the manifest is in hand at publication and discarded on
the way to the archive. The fix is to carry what is already computed, not to
compute anything new.

Same shape as `bug-t-a-tier-job-identifier-is-a-selector-doing-double-duty-as-a-label`,
where `step_src` is recorded per red and simply does not reach the identifier.
**Twice in one evening, a field that exists one layer away from the reader who
needs it.**

## Not this ticket

Whether pin-verify and requested-verify *should* write a full report `.md` is a
separate and larger question — a report is a committed artefact and these paths
may have been made quiet on purpose. **The archive row is the cheap half**: it
is already being written, it is already keyed by sha, and adding the manifest
fields to it makes the verdict readable without adding a file to the repo.
Do that first and decide the report separately.
