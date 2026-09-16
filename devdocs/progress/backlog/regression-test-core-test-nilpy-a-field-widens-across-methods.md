---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 19, `/tmp/test_nilpy_fldwiden26 | diff -u test/test_nilpy_a_field_widens_across_methods.expected -`, which names `test/test_nilpy_a_field_widens_across_methods.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_a_field_widens_across_methods.npy at 67f0878f2e59 in step 2/19, `/tmp/test_nilpy_fldwiden26 | diff -u test/test_nilpy_a_field_widens_across_methods.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T01:50:14Z
- **Test source:** test/test_nilpy_a_field_widens_across_methods.npy test/test_nilpy_a_field_widens_across_methods.expected
- **Failing step:** line 2 of 19 of the job's recipe; it names `test/test_nilpy_a_field_widens_across_methods.expected`.
  ```
  /tmp/test_nilpy_fldwiden26 | diff -u test/test_nilpy_a_field_widens_across_methods.expected -
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_a_field_widens_across_methods.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-4071561/test_nilpy_fldwiden26  [code=1355544B  data=94150B  bss=54996B  procs=2216]
--- test/test_nilpy_a_field_widens_across_methods.expected	2026-09-11 21:30:21.988071443 +0200
+++ -	2026-09-16 03:46:42.415308046 +0200
@@ -6,7 +6,7 @@
 (10, 20)
 (1, 9.5, 3)
 (1, 's', 3, 1.25)
-0.5
+0
 2.5
 1 2 3
 (1, 9.5, 3) 1 9.5 3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
