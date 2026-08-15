---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_lambda_in_range_comprehension.npy red at 4c9da77f9368 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T08:39:52Z
- **Test source:** test/test_nilpy_lambda_in_range_comprehension.npy test/test_nilpy_lambda_in_range_comprehension.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_lambda_in_range_comprehension.npy'` at 4c9da77f9368ee00abe9614ae864cee612275db6

## Range
bad `unknown`, range **unknown** (first run covering this job at this tier, so there is no earlier passing sha to bound it) — **no idle bisect will happen**; this one needs hand-triage.

## Log tail
```
ok: /tmp/testmgr-scratch-2453462/test_nilpy_lamcomp26  [code=2275438B  data=44924B  bss=11396B  procs=1645]
--- test/test_nilpy_lambda_in_range_comprehension.expected	2026-08-15 07:32:04.884997473 +0200
+++ -	2026-08-15 10:33:43.422813313 +0200
@@ -2,7 +2,7 @@
 list [30, 30, 30]
 str ['c', 'c', 'c']
 pinned [0, 1, 2]
-genexpr [2, 2, 2]
+genexpr []
 dict [1, 1]
 step [9, 9, 9, 9]
 empty []

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
