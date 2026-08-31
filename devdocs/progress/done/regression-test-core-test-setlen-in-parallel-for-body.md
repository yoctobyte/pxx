---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_setlen_parfor26)" "PARALLEL SETLEN OK total=8000"`. The job's own `src` (`test/test_setlen_in_parallel_for_body.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_setlen_in_parallel_for_body.pas at d28b77ce5d88 in step 2/2, `tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_s` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T06:11:26Z
- **Test source:** test/test_setlen_in_parallel_for_body.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_setlen_parfor26)" "PARALLEL SETLEN OK total=8000"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_setlen_in_parallel_for_body.pas'` at d28b77ce5d8887b6c143aaeafa9e77666b643d8b

## Range
> **The named sha `d28b77ce5d88` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `d28b77ce5d88`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-2394002/test_setlen_parfor26  [code=126744B  data=5728B  bss=42612B  procs=277]
expect_same: MISMATCH [test_setlen_parfor26]
--- expected
+++ actual
@@ -1 +1 @@
-PARALLEL SETLEN OK total=8000
+PARALLEL SETLEN OK total=7968

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-31 — auto-closed by the seven watcher: `test-core#src:test/test_setlen_in_parallel_for_body.pas` passes at d28b77ce5d88 (tier full); it was red at d28b77ce5d88. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
