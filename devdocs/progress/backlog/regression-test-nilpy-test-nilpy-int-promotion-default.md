---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_int_promotion_default.npy red at 459e96f985d1 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T09:13:26Z
- **Test source:** test/test_nilpy_int_promotion_default.npy test/test_nilpy_int_promotion_default.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_int_promotion_default.npy'` at 459e96f985d1588fac20836b151341cf7e967a61

## Range
bad `459e96f985d1`, last good `137a182ad46a`, 70 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1497482/test_nilpy_intpromo26  [code=2453212B  data=48768B  bss=13532B  procs=1913]
--- test/test_nilpy_int_promotion_default.expected	2026-08-07 07:30:11.503759064 +0200
+++ -	2026-08-16 11:03:03.818137813 +0200
@@ -40,10 +40,10 @@
 -4
 2
 15
+[]
+0
 [3000000000, 3000000001, 3000000002]
-4
-[3000000000, 3000000001, 3000000002]
-[3000000000, 3000000001, 3000000002]
+[]
 18446744073709551621 6148914691236517207 0
 5
 -6148914691236517207 0

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
