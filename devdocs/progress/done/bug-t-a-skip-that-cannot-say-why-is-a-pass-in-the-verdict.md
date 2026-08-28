---
slug: bug-t-a-skip-that-cannot-say-why-is-a-pass-in-the-verdict
track: T
type: bug
prio: 50
status: done
blocked-by: []
summary: "testmgr records `reason: \"\"` on every skipped job. A full-tier sweep on 2026-08-26 skipped ~50 jobs — every conformance shard and every real-program corpus — and the report could not say why for any of them. The verdict line says RED/GREEN with no skip count, so a run that silently covered 3031 of 3081 jobs reports in the vocabulary of one that covered all of them."
owner: pxx-a5
---

# A skip that cannot say why is a pass in the verdict

- **Type:** bug (harness reporting) — **Track T** (`tools/testmgr.py`). T's own
  file; no ticket was needed to fix it, this exists because the session ended
  first.
- **Found:** 2026-08-26, in the `e7c0d1d2a` full-tier sweep.

## What happened

The sweep reported `verdict: RED`, 3081 jobs, `unreached: 0`, `timed_out: false`.
Sound. But ~50 jobs carried `status: "skip"`, including:

- all 6 `test-pascal-conformance` shards
- all 36 `test-c-conformance` shards (x86-64, i386, aarch64, arm32, riscv32)
- every real-program corpus: `test-lua`, `test-lua-cross`, `test-cjson`,
  `test-zlib`, `test-fgl`, `test-fpjson`, all four `test-sqlite-threads`
- `lib-test lib_dns_wire.pas`, `test-core crtl_tiny_regex_match.c`

**`reason` was the empty string on every one of them.** The most likely cause is
that the corpora were absent from a scratch worktree — but the report cannot say
so, so a reader has to guess, and a reader in a hurry will not.

## Why this is the harness's bug and not the reader's

`unreached: 0` and `timed_out: false` are both true and both reassuring. The tier
covered **3031 of 3081 jobs** and reported in exactly the vocabulary it would
have used for 3081. The missing 50 are not a random 1.6%: they are the entire
conformance suite and every real program the project compiles — the densest
signal there is. A promotion decision resting on *"real programs still work"*
would have found nothing in this report to contradict it, because the jobs that
answer that question did not run and did not say so.

This is the same defect family the project has been pulling out all week — an
incomplete step reporting in the vocabulary of a complete one — and
`devdocs/dev/differential-probes.md` already states the rule as **rule 3: a skip
is not a pass**, for the shell probes. `fpc_diff_probe.sh` counts and prints its
skips, and prints `(a SKIP is not a pass -- fix the case or drop it)` when there
are any. testmgr, which is the instrument every verdict in the project comes
from, does not.

## Fix

1. **Populate `reason`** at every site that produces a skip — missing corpus,
   absent binary, unmet precondition, `pxx.skip` entry — so the report says which.
2. **Put the count in the verdict line**: `RED, 50 skipped` / `GREEN, 50 skipped`,
   never bare `GREEN`. The number is what makes a reader ask the question at all.
3. **Name the skipped set in the report body**, grouped by reason, the way the
   red list is named.

Worth considering while in there: a skip whose reason is *"the corpus is not
present"* is a different fact from a skip whose reason is *"this job is
deliberately not run in this tier"*, and only the first is a coverage hole. If
they are distinguishable at the call site, distinguish them in the output.

## 2026-08-28 — done, all three items, plus three more instances found in here

| item | where |
| --- | --- |
| 1. populate `reason` at every skip site | `70f9b9976` |
| 2. skip count in the verdict | `bd9c0898e` |
| 3. name the skipped set, grouped by reason | `bd9c0898e` |
| the "worth considering" distinction | `coverage_holes`, counted apart from self-guards |

Jobs carry `skip_reason`, set where the skip happens: the corpus tree by name,
the absent tool by name, or **the recipe's own SKIP line** — the one reason only
the job knows, which is why `_self_skipped()` now returns that line instead of a
bool. The report JSON gains `skips` (count, `coverage_holes`, the set grouped by
reason) beside `unreached`, always present so a consumer tests a field rather
than inferring from absence.

Published side, which is what the ticket was actually about: the uncapped
archive had **no skip key at all**, so no query over it could distinguish a
sweep that covered 3031 of 3081 jobs from one that covered 3081. It now carries
`skips` and `skip_holes`; the report markdown carries both in its header, a
banner above the fold when jobs did not run on this box, and a collapsed listing
by reason.

**Three further instances of the same family, found while in here:**

1. the summary count was computed **before** the run, so a job that skipped
   itself *during* the run stayed in the denominator and was never named — it
   read as a job that ran and did not pass;
2. one hardcoded `(corpus absent)` label described the FPC-canary skips wrongly
   for seven weeks. A wrong reason is worse than none: it answers the question
   the reader would otherwise have asked;
3. an advisory job that SKIPPED rendered as **NOTICE**, because "advisory and
   not pass" is true of a skip — so the canary on a box without `fpc` printed in
   the vocabulary of a canary that ran and found drift.

The third was caught by **forcing a real skip end to end** (`FPC=` overridden to
a name that is not on PATH), not by reading the state expression, which looks
correct. The unit guards would all have passed with it broken.

21 guards in `tools/testmgr_skip_reason_devtest.py`; the four named breaks plus
both banner breaks are mutation-tested.

### What this does to `decide-t-should-a-skip-close-an-open-regression` (open in U)

It does not decide it, and deliberately does not try to — but it changes the
evidence available to whoever does. That decision asks whether a skip should
close an open regression. Until now a skip could not say *why*, so the two cases
the decision turns on were indistinguishable in the data: a job skipping because
this box lacks a corpus (the run proves nothing, and closing on it would be
closing on silence) versus a job the recipe deliberately guards out (where a
close may be right). `coverage_holes` separates exactly those, and
`closed_by` (`0fc679056`, earlier today) already records which kind closed a
regression. So the U decision can now be made on recorded data rather than on a
guess about what skips mean.

**Not done, deliberately:** closure behaviour is unchanged. A landed mechanism
narrowing a pending decision without anyone noticing is its own failure mode,
so this is written down rather than acted on.

## Provenance of the finding

Surfaced by the sweep in
[[regression-n-three-nilpy-dispatch-tests-red-and-invisible-to-native]], where
reporting the coverage gap honestly took a paragraph of prose that a single line
of harness output should have carried. Fixing the instrument was chosen over
re-running the skipped set: a re-run answers one sweep, the fix answers all of
them.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
