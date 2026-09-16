---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 2, `/tmp/test_nilpy_getitemcall26 | diff -u test/test_nilpy_getitem_on_a_call_result.expected -`, which names `test/test_nilpy_getitem_on_a_call_result.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_getitem_on_a_call_result.npy at 67f0878f2e59 in step 2/2, `/tmp/test_nilpy_getitemcall26 | diff -u test/test_nilpy_getitem_on_a_call_result.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T02:10:51Z
- **Test source:** test/test_nilpy_getitem_on_a_call_result.npy test/test_nilpy_getitem_on_a_call_result.expected
- **Failing step:** line 2 of 2 of the job's recipe; it names `test/test_nilpy_getitem_on_a_call_result.expected`.
  ```
  /tmp/test_nilpy_getitemcall26 | diff -u test/test_nilpy_getitem_on_a_call_result.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_getitem_on_a_call_result.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-4094684/test_nilpy_getitemcall26  [code=1351448B  data=88336B  bss=56148B  procs=2197]
--- test/test_nilpy_getitem_on_a_call_result.expected	2026-09-11 21:30:22.007070834 +0200
+++ -	2026-09-16 04:07:05.394094183 +0200
@@ -8,8 +8,4 @@
 in-dict 8
 loop 11
 loop 12
-write-named 1
-write-then-read 2
-write-call-result
-key-call 7
-TEST-OK
+write-named 
\ No newline at end of file
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
