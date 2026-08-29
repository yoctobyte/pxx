---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_fallback_import.npy red at 3ad067ed395d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T17:27:20Z
- **Test source:** test/test_nilpy_fallback_import.npy tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_fallback_import.npy'` at 3ad067ed395d10bcd4df418b78ff2031206c4d94

## Range
> **The named sha `3ad067ed395d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3ad067ed395d`, last good `7b8f0afc54f8`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
note: pkgprobe_sub -> mimic_pkgprobe_sub (shim, subset)
ok: /tmp/testmgr-scratch-363037/test_nilpy_fallback26  [code=1254089B  data=55068B  bss=50220B  procs=1855]
Unhandled exception: TypeError: object is not callable — the name is None (an import that did not resolve, or a value never assigned)
expect_same: MISMATCH [test_nilpy_fallback26.2]
--- expected
+++ actual
@@ -1 +1 @@
-hello fallback
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
