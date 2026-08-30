---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_zero_argument_builtin_constructors.npy red at dc798834ba33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T18:15:54Z
- **Test source:** test/test_nilpy_zero_argument_builtin_constructors.npy test/test_nilpy_zero_argument_builtin_constructors.expected

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_zero_argument_builtin_constructors.npy'` at dc798834ba33aee86e1af089a8e2579da57087e7

## Range
> **The named sha `dc798834ba33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `dc798834ba33`, last good `fc9e258e1b71`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1206433/test_nilpy_zeroctor26  [code=1285912B  data=78616B  bss=8440468B  procs=1878]
--- test/test_nilpy_zero_argument_builtin_constructors.expected	2026-08-29 16:03:42.888941360 +0000
+++ -	2026-08-30 18:14:18.883712011 +0000
@@ -6,7 +6,7 @@
 True True True
 True True True
 True True True True
-400
+47200
 [1, 2] 2 {'k': 0}
 ('', 0, 1)
 ('x', 3, 1)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-30 — auto-closed by the seven watcher: `test-core#src:test/test_nilpy_zero_argument_builtin_constructors.npy` passes at e2d1d1e047df (tier native); it was red at dc798834ba33. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
