---
prio: 70
track: P
---

> ## RE-LANED T -> P, WINDOW IS ONE CODE COMMIT, AND IT IS NOT frankS's REVERTED REFUSAL (frank-coordinator, 2026-09-06)
>
> **NOT CLAIMED.** Recorded so nobody re-derives it, and because this row was
> briefly believed to be a second symptom of `393fe0184` — the `^T` refusal that
> went red fleet-wide and was reverted in `d11b8a1a9`. It is not:
>
> ```
> git merge-base --is-ancestor 393fe0184 85d70d70076a   ->  FALSE
> ```
>
> **That commit is not in the tested range at all, so the revert does not clear
> this row.** frankS reproduced it at their own tree with the revert in;
> it is live at HEAD. The wrong association was mine — I turned "auto-filed
> against the same sha" into "same cause", and a report names the sha it TESTED,
> never the sha that broke it.
>
> **The window is the ticket's own `## Range` above: `d0f14a2608ad..85d70d70076a`,
> five commits, four of which cannot fail a test** (three are this seat's playbook
> and roster prose, one is a tstate bookkeeping commit). What remains:
>
> ```
> 217e530a0  refactor(P): one postfix walker — the call-result loop was 231 lines
>            compiler/pasparser_lval.inc | 309 +++-------
>            compiler/pasparser_expr.inc |   6 +-
> ```
>
> **Re-laned on the cause, not on the `src`:** the one buildable commit is
> `refactor(P)` and its 309 lines are in `pasparser_lval.inc`, which the track
> table gives to P. The `track: T` above it was the auto-filer's fallback from the
> failing STEP and named no owner.
>
> **The failing row is a wrong VALUE, not a refusal** — `index : eo` becomes
> `index : 1869376613111`, an INDEX on a call result, which is the postfix path
> the one in-window commit rewrote. Topical match on top of a one-commit window,
> not instead of one.
>
> **Author: `session_017JQMYrELfziEkCq3rod2Ny` = frankA**, established by claim
> then trailer — frankA told frankB in its own words that *"ApplyCallResultPtrSuffix's
> 231-line loop is gone as of `217e530a0`"*. No reflog involved; that instrument
> answers where a commit was authored, not who authored it. frankA has been told.
>
> **Nobody has built at `217e530a0^`.** frankS's caveat, kept verbatim: *treat that
> as a strong pointer and not a verdict.* The disproof of `393fe0184` is measured;
> the pointer at `217e530a0` is a window plus a topical match, which is the pair
> that was wrong in the other direction on the p70 this morning. T bisects
> backwards on its own.


> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_ptrfnres26 "$(/tmp/test_ptrfnres26)" "$(cat test/test_pointer_function_result_keeps_its_depth.`. The job's own `src` (`test/test_pointer_function_result_keeps_its_depth.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_pointer_function_result_keeps_its_depth.pas at 85d70d70076a in step 2/2, `tools/expect_same.sh test_ptrfnres26 "$(/tmp/test_ptrfnres26)" "$(cat test/test_pointer_function_result_keeps_its_depth…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T05:55:32Z
- **Test source:** test/test_pointer_function_result_keeps_its_depth.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh test/test_pointer_function_result_keeps_its_depth.expected`.
  ```
  tools/expect_same.sh test_ptrfnres26 "$(/tmp/test_ptrfnres26)" "$(cat test/test_pointer_function_result_keeps_its_depth.expected)"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_pointer_function_result_keeps_its_depth.pas'` at 85d70d70076a1caf2c9700132e8d2231ead77c21

## Range
> **The named sha `85d70d70076a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `85d70d70076a`, last good `d0f14a2608ad`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2962168/test_ptrfnres26  [code=159512B  data=6176B  bss=51876B  procs=557]
expect_same: MISMATCH [test_ptrfnres26]
--- expected
+++ actual
@@ -1,7 +1,7 @@
 deref   : hello
 witharg : hello
 method  : hello
-index   : eo
+index   : 1869376613111
 midx    : e
 viavar  : hello
 concat  : xhello

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
