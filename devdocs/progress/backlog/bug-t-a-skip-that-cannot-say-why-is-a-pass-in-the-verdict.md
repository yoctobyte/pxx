---
slug: bug-t-a-skip-that-cannot-say-why-is-a-pass-in-the-verdict
track: T
type: bug
prio: 50
status: backlog
blocked-by: []
summary: "testmgr records `reason: \"\"` on every skipped job. A full-tier sweep on 2026-08-26 skipped ~50 jobs — every conformance shard and every real-program corpus — and the report could not say why for any of them. The verdict line says RED/GREEN with no skip count, so a run that silently covered 3031 of 3081 jobs reports in the vocabulary of one that covered all of them."
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

## Provenance of the finding

Surfaced by the sweep in
[[regression-n-three-nilpy-dispatch-tests-red-and-invisible-to-native]], where
reporting the coverage gap honestly took a paragraph of prose that a single line
of harness output should have carried. Fixing the instrument was chosen over
re-running the skipped set: a re-run answers one sweep, the fix answers all of
them.
