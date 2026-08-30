---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_warn_ignored_directives.pas red at 83fb0ef72419 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T13:24:51Z
- **Test source:** test/test_warn_ignored_directives.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_warn_ignored_directives.pas'` at 83fb0ef72419b46cf22dd1ce57885950574d69ef

## Range
> **The named sha `83fb0ef72419` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `83fb0ef72419`, last good `42fde2a7e025`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
expect_same: MISMATCH [test_warn_ignored_directives26.1]
--- expected
+++ actual
@@ -1 +1 @@
-6
+5

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
