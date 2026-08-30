---
prio: 70
track: C
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 16 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cstatic_same_module_dup.c red at 7227f3e0f1f8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T19:49:31Z
- **Test source:** test/cstatic_same_module_dup.c tools/expect_same.sh

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/cstatic_same_module_dup.c'` at 7227f3e0f1f8343547d85f7fc3a32c2f440686dd

## Range
> **The named sha `7227f3e0f1f8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7227f3e0f1f8`, last good `f487ba6f27fe`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
expect_same: MISMATCH [cstatic_same_module.log]
--- expected
+++ actual
@@ -1 +1 @@
-1
+2

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-30 — auto-closed by the seven watcher: `test-core#src:test/cstatic_same_module_dup.c` passes at dbab98d339c7 (tier native); it was red at 7227f3e0f1f8. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
