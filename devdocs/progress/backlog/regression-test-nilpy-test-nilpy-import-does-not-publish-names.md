---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 5, `/tmp/test_nilpy_impub26 | diff -u test/test_nilpy_import_does_not_publish_names.expected -`, which names `test/test_nilpy_import_does_not_publish_names.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_import_does_not_publish_names.npy at 844ccea7a0f2 in step 2/5, `/tmp/test_nilpy_impub26 | diff -u test/test_nilpy_import_does_not_publish_names.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T21:12:05Z
- **Test source:** test/test_nilpy_import_does_not_publish_names.npy test/test_nilpy_import_does_not_publish_names.expected
- **Failing step:** line 2 of 5 of the job's recipe; it names `test/test_nilpy_import_does_not_publish_names.expected`.
  ```
  /tmp/test_nilpy_impub26 | diff -u test/test_nilpy_import_does_not_publish_names.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_import_does_not_publish_names.npy'` at 844ccea7a0f2d80521a71d1c58d65cc0d2d1ef4b

## Range
> **The named sha `844ccea7a0f2` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `844ccea7a0f2`, last good `ff6694727a23`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3654333/test_nilpy_impub26  [code=537698B  data=130352B  bss=102444B  procs=2840  codeseg=540384B]
--- test/test_nilpy_import_does_not_publish_names.expected	2026-09-11 21:30:22.009070770 +0200
+++ -	2026-09-28 22:55:49.403506342 +0200
@@ -1,6 +1,6 @@
-1.5 2 2 1.5
--0.0 -0.0
+1.5 2.0 2.0 1.5
 0.0 0.0
+-0.0 -0.0
 1.5 0.0 3 2 -2
 1 3 1 3
 4.0 6

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
