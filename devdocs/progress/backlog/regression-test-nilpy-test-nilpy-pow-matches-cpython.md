---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_pow_matches_cpython.npy red at 096da361dd93 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T11:09:21Z
- **Test source:** test/test_nilpy_pow_matches_cpython.npy test/test_nilpy_pow_matches_cpython.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_pow_matches_cpython.npy'` at 096da361dd93823dc6aa56f7a344de5f343127ec

## Range
bad `096da361dd93`, last good `459e96f985d1`, 32 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1820057/test_nilpy_pow26  [code=2429383B  data=48620B  bss=10012B  procs=1926]
--- test/test_nilpy_pow_matches_cpython.expected	2026-08-16 01:45:04.069549215 +0200
+++ -	2026-08-16 12:55:50.300756373 +0200
@@ -4,7 +4,7 @@
 2.7181459268249255
 2.7181459268249255
 2.7181459268249255
-ValueError
+(-0+2.8284271247461894j)
 ZeroDivisionError
 1024 1 -8 0.5
 0.125 1e+100 2.25 0.007713560673657699

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
