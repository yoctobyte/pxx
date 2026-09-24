---
slug: bug-t-host-dev-lib-skip-devtest-outgrew-its-budget-and-times-out-the-whole-guards-job
type: bug
track: T
prio: 45
status: done
summary: 'FIXED 2026-09-17 — the cause was a QUADRATIC REGEX, not repetition: `_USES_RE` was `^\s*uses` under re.M, and `compiler/builtin/pylib.pas` alone was 194.241s of a 194.8s total over the 1902 sources scanned. `[ \t]*` makes it line-scoped: whole set 0.2s (1082x), step-7 leg 196s -> 2.01s, devtest 18 guards / 0 FAIL / 4.8s from a 1200.1s TIMEOUT. Match set unchanged, measured byte-identical on all 1902 files. THE PRESCRIBED FIX BELOW ("memoise the parse") WAS WRONG and is left standing as written: the scan opens 1902 DISTINCT files across 2562 jobs, so a memo removes a quarter of the calls and none of the cost — it was built, proved equivalent, measured at ~1x and reverted. ORIGINALLY: tools/host_dev_lib_skip_devtest.py step 7 rescans >1500 recipes per run and now exceeds 1200s, timing out tools-devtest#00 and reddening any full tier'
---

## What

`tools-devtest#00` went TIMEOUT at 1200.1s in the full tier run before pin v411
(2026-09-17), killed by the hang detector rather than the class ceiling —
testmgr said so itself and raised the stored duration on the way out.

It is not a hang. Reproduced standing alone, no contention, load 2.7 on 12
cores: the script is still running at **17 minutes**. The stack, taken with
`PYTHONFAULTHANDLER=1 timeout -s ABRT`:

    tools/testmgr.py:1909 in missing_dev_requirement
    tools/host_dev_lib_skip_devtest.py:183 in main

Step 7 is deliberately the REAL population — its own comment says a synthetic
one "passes and certifies the broken instrument" — so it walks every job of
`test-core`, `lib-test` and `demos` (>1500) and calls `missing_dev_requirement`
on each. That function reads each recipe's `.pas`, strips Pascal comments and
regex-scans every `uses` clause against the fallback roots. The work is
per-job-times-per-source and the job count only grows.

## Why it is not this range's fault

Neither `tools/host_dev_lib_skip_devtest.py` nor `tools/testmgr.py` changed in
`764ee2ed2..9b8475d4e` — the 79-commit `compiler/`+`lib/` range pin v411
carries. Its last two touches (`8c76b20eb`, `324304f1e`) predate v410. **The
population grew under a fixed budget**, which is why it arrives as a cliff at
the 1200s cap rather than as a slope anyone watched.

## Why the assertion must not simply be relaxed

The row it guards is `0 false skips`, and its own comment records the three
bugs that died on it in sequence — 83 false skips, then 47, then 2, then 0.
A false skip is SILENT: it removes coverage and reports success. So do not
sample the population or drop step 7; the whole value is that it is the real
recipe set and not a synthetic one.

## Shape of the fix (not started)

The scan re-reads and re-parses the same `.pas` files once per job that names
them, and most recipes in a target share sources. Memoise on the source path —
`_strip_pascal_comments` plus the `uses` extraction is the expensive half and
is a pure function of file content. Cache `_in_tree_unit` lookups too; they
`os.path.exists` the same candidate roots thousands of times. Neither changes
what the guard asserts, which is the point: this is a speed fix and the row
must still be able to fail. Positive control: with the memo in place, inject a
recipe whose `-I` names an absent dir and assert it is still reported.

## Notes

Found during the pin v411 tier and recorded in `8d9d69bdc` as one of three
graded reds. It does not gate a pin — only the self-host fixedpoint does — but
it reddens every full tier until fixed, and a tier that is red for a known
tooling reason is a tier whose real reds are harder to see.

## FIXED 2026-09-17 (frankb-56) — and BOTH prescribed shapes were wrong

FIXED: the cause was not repetition but a QUADRATIC REGEX on one file. _USES_RE was `^\s*uses` with re.M -- `^` matches at every line start and `\s` matches newlines, so the scan restarts through blank lines from each line start. `[ \t]*` makes it line-scoped. Measured over the 1902 sources the guard opens: compiler/builtin/pylib.pas ALONE was 194.241s of a 194.8s total, the other 1901 files 0.6s; whole set now 0.2s, 1082x. Full step-7 leg 196s -> 2.01s (min of 3, interleaved). Devtest: 18 guards, 0 FAIL, 4.8s, from a 1200.1s TIMEOUT. THE TICKET'S PRESCRIBED SHAPE WAS WRONG AND SO WAS MY FIRST ATTEMPT: 'memoise the parse' was written, proved equivalent over 2399 files, and measured at ROUGHLY 1x -- the scan opens 1902 DISTINCT files across 2562 jobs, so a cache removes a quarter of the calls and none of the cost. Memo reverted rather than shipped beside the real fix. The stack sample named testmgr.py:1909 correctly and a stack says WHERE, never WHY; repetition and per-call cost land on the same line. Match set unchanged and MEASURED: names byte-identical on all 1902 files. Assertions untouched -- 0 false skips on a provisioned box, absent-roots control still fires on 11 jobs

## Log
- 2026-09-17 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2f06c2423.
