---
slug: bug-t-a-failing-grep-q-step-leaves-the-archive-unable-to-say-what-broke
track: T
prio: 45
type: bug
status: done
owner: "frankB"
created: 2026-09-09
found-by: frank-seven
tags: [testmgr, tstate, reporting, instrument]
blocked-by: []
summary: "FIXED 2026-09-09, three parts. (1) job_reason() returned '' for a red whose log was 0 bytes -- the spelling its own docstring reserves for 'gone or unreadable' -- so a readable-and-silent log and a missing one published as one finding; it now names the failing step from the .step marker. (2) The bigger half, not in the original report: twatch's `## failure detail` block reads the LOG FILE, not the report, so fixing job_reason alone changed nothing a reader sees -- a 0-byte log emitted a bare empty fence and a REAPED log emitted nothing at all, and every report read after LOGDIR_KEEP_SECS takes that second branch. Both now say which and fall back to reason/step_line. (3) `line 35 of 10`: step_i indexes job.lines, step_n counted only non-comment lines; censused across devdocs/progress at 34 impossible citations of 449 (7.6%), 9 distinct shapes, sitting in auto-filed regression tickets. Guard: tools/testmgr_red_is_self_describing_devtest.py, 12 rows driving the real Job/report_job/write_report_md."
---

# The two defects

**1. A silent assertion produces a silent archive.** `grep -q` is correct as a
recipe step and wrong as the LAST thing a failing job does. The fix is not to
ban it — it is to make the harness capture enough context that a red is
self-describing: echo the assertion and its subject on failure, or have testmgr
tee the step's command line into the job log when the log would otherwise be
empty. A 0-byte log is itself a detectable condition and should never be
published as a verdict without a note saying the step produced no output.

**2. `line 35 of 10`.** Small, and it is exactly the field a reader uses to
locate the step. Find where the numerator and denominator are computed against
different line sets (almost certainly raw recipe lines vs executable ones) and
make them agree, or drop the denominator rather than print a false one.

# Why this is worth p45 rather than a tidy-up

Three cheap methods for locating this failure all named an innocent row, in one
pass, on one bug:

- the tstate reason string named four scripts that were never implicated (it
  reports the loop's progress, not its failures — see
  `bug-t-the-tstate-reader-guard-is-enforced-in-a-tier-no-per-fix-gate-runs`)
- the ticket's step number said 35 of 10
- counting recipe lines by hand landed on `test_asm_swap`, which passes

None of the three ERRORED. All three answered. That is the house failure mode
sitting in the reporting path, where its cost is paid by whoever is debugging
something else — and it is what turned a one-line harness bug into two sessions'
work.

# Provenance

frank-seven, on seven, reaching the real cause only via the auto-filed ticket's
rendered command after the report's failure-detail block came back empty.

## 2026-09-09 (frankB) — FIXED, both halves, and the second one was worse than filed

**1. An empty log is not an unreadable one.** `job_reason()`'s own docstring
reserves `""` for *"the log is gone or unreadable ... never a claim that the job
failed for no reason"* — and a red whose log was 0 bytes published exactly that
`""`. Now it returns a note naming the silent step, recovered from the `.step`
marker `Job.script()` already writes before every recipe line. That marker is
also why this is right for a **timeout**: it names the line the job was sitting
in, which is the case where the log says least of all.

Not written into the log during the run: `script()`'s own comment refuses to
salt the log with harness output, because the log is what `job_reason()` and
`diagnostic_lines()` read.

**NOISE-ONLY IS NOT EMPTY, and the first version of this fix got that wrong.**
`make: *** [t] Error 1` is a real line carrying nothing the status and name do
not already say; `job_reason_devtest.py` has always asserted it yields `""` and
that argument is untouched. Claiming *"the step printed nothing"* about a log
that printed that would have been a second false statement in the field this
change exists to stop lying in. **Two existing guards caught it** — which is the
whole case for running the neighbours of what you touch.

**2. The report block reads the LOG FILE, not the report — so fixing
`job_reason` alone fixed nothing a reader sees.** `write_report_md`'s
`## failure detail` block opened the log and emitted a bare empty ``` pair for a
0-byte log, and **nothing at all** when the log dir had been reaped. Both read
as *"the detail is elsewhere"*. It now says which case it is and falls back to
`reason` and `step_line` — the two fields that survive the run, `log` being a
path in a temp dir the OS reaps. **The reaped branch matters more than the
empty one over time: every report read after `LOGDIR_KEEP_SECS` takes it.**

**3. `line 35 of 10` — and it is 34 citations, not one.** `Job.script()` numbers
`self.lines` (every line, comments included, because `failed_step()` indexes
`lines[i]`); `step_n` counted only the non-comment lines. Numerator and
denominator over different sets. `step_n` is now `len(job.lines)`.

Censused across `devdocs/progress/`: **449 step citations, 34 of them impossible
(7.6%), in 9 distinct shapes** — `line 12 of 4`, `line 28 of 3`, `line 53 of 47`,
`line 95 of 57` among them. They sit in auto-filed regression tickets, which is
exactly where a reader uses the number to find the step. The ticket filed one
instance; the field has been wrong at that rate for as long as it has existed.

## Guard

`tools/testmgr_red_is_self_describing_devtest.py`, 11 rows, driving the real
`Job`, the real `report_job()` and the real `write_report_md()` — not stubs and
not a constants grep, because **a branch that exists and is unreachable passes a
constants check and fails the reader**, which is this ticket's own defect class.

Negative controls, all drawn from the population: a gone log, a never-launched
job and a noise-only log must all still read as unknown; a log with output must
render exactly as before. Positive control for the citation: a fixture whose
comments outnumber its commands, asserted to be one the OLD denominator would
have undercut — a recipe with no comments would have passed the old code too.
And an aim check that `script()` still numbers the list `step_n` measures, since
otherwise both halves move together and only the LINE TEXT goes wrong, which is
the same defect one layer down and silent.

**Superseded one row in `job_reason_error_devtest.py`** (`an empty log still
reads as 'unknown'`) with the reasoning inline. It was a **no-change control for
the error-scan widening** — section 3 of that file is *"changes NOTHING
otherwise, oracle: the pre-fix code"* — not a policy about empty logs. That
reading is what made it look like an argued rule.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6aa50d6eb.
