---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 12, `/tmp/test_nilpy_modmemval26 | diff -u test/test_nilpy_module_member_as_a_value.expected -`, which names `test/test_nilpy_module_member_as_a_value.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_module_member_as_a_value.npy at 5dbee723e228 in step 2/12, `/tmp/test_nilpy_modmemval26 | diff -u test/test_nilpy_module_member_as_a_value.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T00:56:57Z
- **Test source:** test/test_nilpy_module_member_as_a_value.npy test/test_nilpy_module_member_as_a_value.expected
- **Failing step:** line 2 of 12 of the job's recipe; it names `test/test_nilpy_module_member_as_a_value.expected`.
  ```
  /tmp/test_nilpy_modmemval26 | diff -u test/test_nilpy_module_member_as_a_value.expected -
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_module_member_as_a_value.npy'` at 5dbee723e228cfb986a5561e78ccffb7e9a153ec

## Range
bad `5dbee723e228`, last good `1704e17de6f3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3684418/test_nilpy_modmemval26  [code=1347352B  data=87117B  bss=55588B  procs=2195]
Unhandled exception: TypeError: cannot construct Box through a class VALUE: its constructor takes 13 at position 1, which this path cannot marshal
--- test/test_nilpy_module_member_as_a_value.expected	2026-09-11 21:30:22.016070546 +0200
+++ -	2026-09-16 02:52:49.888149507 +0200
@@ -10,4 +10,3 @@
 <function 
 3 b
 7
-11

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
