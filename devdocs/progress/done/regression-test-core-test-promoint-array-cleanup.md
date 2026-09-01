---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 3 is `tools/expect_same.sh test_promoac26 "$(/tmp/test_promoac26 | tail -1)" "promoint-array-cleanup 39000/39000"`. The job's own `src` (`test/test_promoint_array_cleanup.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_promoint_array_cleanup.pas at 145e7a11dfed in step 2/3, `tools/expect_same.sh test_promoac26 "$(/tmp/test_promoac` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T14:51:43Z
- **Test source:** test/test_promoint_array_cleanup.pas tools/expect_same.sh
- **Failing step:** line 2 of 3 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_promoac26 "$(/tmp/test_promoac26 | tail -1)" "promoint-array-cleanup 39000/39000"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_promoint_array_cleanup.pas'` at 145e7a11dfede48852248541873e281b95aacd79

## Range
> **The named sha `145e7a11dfed` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `145e7a11dfed`, last good `b07f946af655`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-3868153/test_promoac26  [code=204568B  data=7772B  bss=42640B  procs=351]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_promoac26]
--- expected
+++ actual
@@ -1 +1 @@
-promoint-array-cleanup 39000/39000
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-core#src:test/test_promoint_array_cleanup.pas` passes at 2017b6eac619 (tier native); it was red at 145e7a11dfed. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
