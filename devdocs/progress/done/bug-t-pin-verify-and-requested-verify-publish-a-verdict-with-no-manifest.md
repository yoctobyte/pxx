---
slug: bug-t-pin-verify-and-requested-verify-publish-a-verdict-with-no-manifest
track: T
prio: 60
type: bug
status: done
found: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "CORRECTED 2026-09-06, and the correction halves it. Only ONE path publishes a verdict with no manifest anywhere: the REQUESTED-VERIFY path (9-key archive rows, 10 of them, no report `.md` in 10 of 10 — the one apparent exception, `1d8db8667267`, has a report from a NATIVE run at the same sha, which is a different run). PIN-VERIFY does NOT belong in that claim: its 8 rows are 10-key and thin, but a full report `.md` exists for every one of them, with a timestamp identical to the row's to the second, carrying `skips`, `skip_holes`, NEW-RED and STILL-RED. So for pin-verify the manifest is written and only the ARCHIVE ROW is short — a queryability gap, not a missing answer. The original filing said neither path writes a report; that was read off a daemon log line (`twatch: verifying PIN v406 … at full` with no `report=`), which announces the START of a verify, not its publication. FIX, now two different sizes: for pin-verify, carry into the archive row what the report already holds. For requested-verify, there is no report at all, and it clears the request queue while telling nobody what was red — the manifest exists at publication (the publishing log line names the failing jobs) and is dropped. DO NOT audit the 92 14-key rows: clean schema cutover 2026-08-31, healthy."
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


## CORRECTION 2026-09-06 — pin-verify DOES write a report, and I had it wrong

The filing above says neither special path writes a report. **That is false for
pin-verify**, and the way it was wrong is the same shape as everything else in
this ticket.

I read it off a daemon log line:

```
twatch: verifying PIN v406 (1b903c1ddaf2) at full          <- no report=
```

**That line announces the START of a verify, not its publication.** Absence of
`report=` on it says nothing about whether a report was written later. I treated
a log line about one event as evidence about a different one.

### What the artefact says

For every 10-key (pin-verify) row, a report `.md` exists at that sha whose own
`tier:` is `full`, with a timestamp **identical to the row's, to the second** —
8 for 8:

```
row 2026-09-01T21:40:34   report 2026-09-01T21:40:34   delta +0.0 min
row 2026-09-02T10:04:54   report 2026-09-02T10:04:54   delta +0.0 min
   … 6 more, all +0.0 …
row 2026-09-06T19:43:25   report 2026-09-06T19:43:25   delta +0.0 min
```

And the content is complete. `20260906T194325Z-1b903c1-seven.md` (v406's own
pin-verify) carries `skips: 7`, `skip_holes: 2`, a coverage banner, a by-reason
skip list, `## NEW-RED` and `## STILL-RED`.

**So pin-verify's manifest is written. Only its archive ROW is short.** That is
a queryability gap — the answer exists in the repo and not in the ndjson — and
it is a much smaller thing than "publishes a verdict with no manifest".

### The request path is unchanged and is the real one

10 of 10 requested-verify rows have **no report at any sha**, except
`1d8db8667267`, whose report is from a **native** run — a different run at the
same sha. That is the confound that nearly fooled me a second time: a report is
named by sha, and a sha can be tested by more than one tier, so *"is there a
report for this sha"* is not *"did this run write one"*. Matching the report's
own `tier:` and its timestamp is what separates them.

### On the proposed detector, tested rather than adopted

*"Does a report `.md` exist for this sha"* was suggested as a shape-independent
detector, on the argument that key counts have already changed once. **Measured,
it does not separate thin from healthy:** 398 of 398 normal rows have a report,
but so do 9 of 18 thin ones. What it actually detects is the **request path**,
cleanly. That is still worth having — it is exactly the check that would have
stopped `1d8db8667267` being reported to the fleet as satisfied — but it is a
request-path detector, not a thin-row detector, and calling it the latter would
put the next reader back where I just was.

## Log
- 2026-09-06 — resolved, commit Both halves landed. PIN-VERIFY half: the archive row carried 10 keys where an ordinary row carries 17, so skips, skip_holes, skip_hole_jobs, still_red, timed_out, unreached and code_fp were absent on exactly the rows describing the artifact every track builds against. skip_holes is the sharp one -- CLAUDE.md's rule is that skip_holes == 0 does not mean every job ran, and without the key you cannot even ask, so a GREEN pin verify covering 3031 of 3081 jobs and one covering 3081 were indistinguishable. The report held all of them and the row dropped them: the same shape as the hardcoded new_red [] fixed in that writer earlier, an absent value in a file whose other rows train the reader to read a measurement. still_red is DERIVED (reds minus new_red) so it cannot disagree. REQUESTED-VERIFY half: it wrote no report at all -- every requested row in the archive, every host, all time, had none, so the row was the only record the run happened and somebody asked for each one. It writes one now. The labelling needed care: NEW-RED/FIXED/STILL-RED are all claims about a PREVIOUS state and verify_requested deliberately does not walk the HEAD progression, so a fifth section says what is known (red HERE, unclassified) with parent_tested: none as the front-matter half. Guards: twatch_requested_report_devtest.py (12 rows) whose control renders the same red under unclassified_red and under still_red and asserts the two are DISTINGUISHABLE in the markdown a human reads -- a section rendering identically to STILL-RED would be a distinction existing only in the author's head while every other row passed. Verified failable: collapsing the category back into STILL-RED reddens 3 rows including the control. devtest_pin_verify's source-shape window was re-anchored to the writer rather than a magic 900 chars, controlled by simulating the original defect against the new window..
