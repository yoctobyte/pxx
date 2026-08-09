---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_from_import_as_alias.npy red at 954727cee668 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-09T10:56:31Z
- **Test source:** test/test_nilpy_from_import_as_alias.npy test/test_nilpy_from_import_as_alias.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_from_import_as_alias.npy'` at 954727cee6680daf514fcd5bb929814a1ca3c522

## Range
bad `954727cee668`, last good `29d980110b58`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1087190/test_nilpy_fromas26  [code=1580306B  data=35912B  bss=8820B  procs=1307]
Segmentation fault (core dumped)
--- test/test_nilpy_from_import_as_alias.expected	2026-08-03 00:47:14.696790522 +0200
+++ -	2026-08-09 12:46:14.091729258 +0200
@@ -2,10 +2,3 @@
 3 3
 8 10
 9
-9
-4
-3 12 3
-3 14
-99
-3
-3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-09 — auto-closed by the plexus watcher: `test-nilpy#src:test/test_nilpy_from_import_as_alias.npy` passes at 85179011f728 (tier full); it was red at 954727cee668. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
