---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_exception_typed26 "$(/tmp/test_exception_typed26)" "$(printf '41\n42\n43\n44\n45')"`. The job's own `src` (`test/test_exception_typed.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_exception_typed`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_exception_typed.pas at 83095f299651 in step 2/2, `tools/expect_same.sh test_exception_typed26 "$(/tmp/test_exception_typed26)" "$(printf '41\n42\n43\n44\n45')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T15:40:14Z
- **Test source:** test/test_exception_typed.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_exception_typed26 "$(/tmp/test_exception_typed26)" "$(printf '41\n42\n43\n44\n45')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_exception_typed.pas'` at 83095f299651eaf6c88fdff058895ed3d8c68e08

## Range
> **The named sha `83095f299651` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `83095f299651`, last good `e2287257920f`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1634129/test_exception_typed26  [code=26377B  data=5312B  bss=35732B  procs=155  codeseg=28384B]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_exception_typed26]
--- expected
+++ actual
@@ -1,5 +1,3 @@
 41
 42
 43
-44
-45

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-28 — auto-closed by the borg watcher: `test-core#src:test/test_exception_typed.pas` passes at 825fbbc9b7f0 (tier native); it was red at 83095f299651. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
