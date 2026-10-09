---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 2, `/tmp/test_nilpy_modstay26 | diff -u test/test_nilpy_an_imported_modules_names_stay_in_the_module.expected -`, which names `test/test_nilpy_an_imported_modules_names_stay_in_the_module.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_an_imported_modules_names_stay_in_the_module.npy@1 at 39225dde3632 in step 2/2, `/tmp/test_nilpy_modstay26 | diff -u test/test_nilpy_an_imported_modules_names_stay_in_the_module.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-09T14:31:59Z
- **Test source:** test/test_nilpy_an_imported_modules_names_stay_in_the_module.npy test/test_nilpy_an_imported_modules_names_stay_in_the_module.expected
- **Failing step:** line 2 of 2 of the job's recipe; it names `test/test_nilpy_an_imported_modules_names_stay_in_the_module.expected`.
  ```
  /tmp/test_nilpy_modstay26 | diff -u test/test_nilpy_an_imported_modules_names_stay_in_the_module.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_an_imported_modules_names_stay_in_the_module.npy@1'` at 39225dde36328946c03caed301e220c9962173a8

## Range
bad `39225dde3632`, last good `62fc7c1e802a`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-203328/test_nilpy_modstay26  [code=539686B  data=110480B  bss=68508B  procs=2379  codeseg=540384B]
--- test/test_nilpy_an_imported_modules_names_stay_in_the_module.expected	2026-09-29 04:06:33.081705271 +0200
+++ -	2026-10-09 16:26:49.708987201 +0200
@@ -4,4 +4,4 @@
 3 ['a', 'b', 'c'] True
 2 False
 2
-shadowlib-len shadowlib-list 5
+shadowlib-len shadowlib-list 7

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
