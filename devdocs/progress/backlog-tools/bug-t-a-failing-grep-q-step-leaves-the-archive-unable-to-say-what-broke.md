---
slug: bug-t-a-failing-grep-q-step-leaves-the-archive-unable-to-say-what-broke
track: T
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frank-seven
tags: [testmgr, tstate, reporting, instrument]
blocked-by: []
summary: "A recipe row that asserts with a bare `grep -q` prints NOTHING when it fails, so testmgr's per-job log is 0 bytes and the report's failure-detail block is empty -- the archive records that a job went red and cannot say what broke. Confirmed across the two most recent runs on test_libmanifest. The auto-filed TICKET does render the failing command, so for this class the ticket is currently a strictly better artefact than the report it is generated from, which inverts the intended relationship. Second defect, same file: the ticket's step citation reads `line 35 of 10 of the job's recipe` -- a number that cannot be true and that a reader will silently round to 'near the end'. AND THE MANUAL FALLBACK ALSO LIES: counting executable recipe lines by hand from the libmanifest compile lands on test_asm_swap, which passes. Three separate cheap ways to locate this failure, all three naming an innocent row."
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
