---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_opt_store_reload.pas red at c951ec710b33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:52:56Z
- **Test source:** test/test_opt_store_reload.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_opt_store_reload.pas'` at c951ec710b33da734e7141394258135689c3e5fa

## Range
> **The named sha `c951ec710b33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c951ec710b33`, last good `08cbfa20a11d`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
expect_same: MISMATCH [test_opt_sr_O0.4]
--- expected
+++ actual
@@ -15,3 +15,5 @@
 br between
 br after neg
 mem   -112 -112 -110
+reord 635218
+reord2 635317

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
